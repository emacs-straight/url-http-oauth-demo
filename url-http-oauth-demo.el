;;; url-http-oauth-demo.el --- Demo url-http-oauth -*- lexical-binding: t -*-

;; Copyright (C) 2023 Free Software Foundation, Inc.

;; Author: Thomas Fitzsimmons <fitzsim@fitzsim.org>
;; Version: 1.0.2
;; Keywords: comm, data, processes, hypermedia
;; Package-Requires: ((url-http-oauth "0.8.1") 
;;                    (emacs "27.1")) ; for json-parse-buffer
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This package demonstrates OAuth 2.0 authentication and
;; authorization to Sourcehut, using the built-in `url' and
;; `auth-source'libraries and the new `url-http-oauth' package.
;;
;; Background:
;;
;; Sourcehut has implemented OAuth 2.0 for its services.  Its
;; implementation is unique in that it is released as Free Software,
;; and does not require JavaScript for any of the OAuth 2.0 steps.
;;
;; Here is a diagram summarizing the protocol, adapted from RFC 6749:
;;
;;           `url' and `url-http-oauth' implement
;;                  these middle steps
;; +--------+                               +------------------------+
;; |        |--(A)- Authorization Request ->|    (Resource Owner)    |
;; |        |                               |                        |
;; |        |<-(B)-- Authorization Grant ---| You, the Human,        |
;; |        |                               | user of Emacs and      |
;; |        |                               | Sourcehut, performing  |
;; |        |                               | steps in a web browser |
;; |        |                               +------------------------+
;; |        |
;; |        |                               +----------------------+
;; |        |--(C)-- Authorization Grant -->|(Authorization Server)|
;; |(Client)|                               |                      |
;; |        |<-(D)----- Access Token -------| URLs starting with   |
;; | Emacs  |                               | meta.sr.ht/oauth2    |
;; |        |                               +----------------------+
;; |        |
;; |        |                               +--------------------+
;; |        |--(E)----- Access Token ------>| (Resource Server)  |
;; |        |                               |                    |
;; |        |<-(F)--- Protected Resource ---| URLs starting with |
;; |        |                               | meta.sr.ht/query   |
;; +--------+                               +--------------------+
;;
;; For generality¹ there is no web browser automation.  Here is a
;; breakdown of Steps A and B:
;;
;; Step A:
;;      A.1: A request URL is shown in the minibuffer; the minibuffer
;;           prompts for a response URL and waits.
;;      A.2: The user copies the request URL into their web browser of
;;           choice¹.
;;      A.3: The user authenticates to Sourcehut, using the web browser.
;;      A.4: The user authorizes Emacs to access their Sourcehut
;;           resource, using the web browser.
;;      A.5: The web browser redirects to a URL; this redirection may
;;           fail or it may not.  All that matters is the URL itself,
;;           which will contain a "code" query argument.
;;      A.6: The user copies the full "code" URL from the web browser.
;;
;; Step B:   The user pastes the full "code" URL into the minibuffer
;;           and presses RET.
;;
;; The remaining steps, C through F, are all handled within Emacs.
;;
;; 1. For example, when running Emacs in a VT100 terminal emulator
;;    through two SSH hops.
;;
;; 2. For Sourcehut in particular, steps A.2 through A.5 can be done
;;    using EWW because Sourcehut does not need JavaScript.  Today EWW
;;    needs to run in a separate process so it does not conflict with
;;    url-http-oauth, which blocks the minibuffer waiting for the
;;    response URL.
;;
;; Installation:
;;
;; M-x package-install RET url-http-oauth-demo RET
;;
;; Usage:
;;
;; M-x url-http-oauth-demo-get-profile-name RET
;; M-: (url-http-oauth-demo-get-profile-name) RET

;;; Code:
(require 'url-http-oauth)

;;; Tell Emacs that the URL "https://meta.sr.ht/query" uses OAuth 2.0
;;; for authentication and authorization.
;;;###autoload
(url-http-oauth-interpose
 '(;; The client identifier.  Replace
   ;; "00000000-0000-0000-0000-000000000000" with a new client
   ;; identifier generated by the user, or by the Emacs library
   ;; developer, at "https://meta.sr.ht/oauth2/client-registration".
   ("client-identifier" . "00000000-0000-0000-0000-000000000000")
   ;; The URL at which the `url-http-oauth-demo' package will access
   ;; resources.  Everything that follows is for authentication and
   ;; authorization to satisfy OAuth 2.0 requirements.
   ("resource-url" . "https://meta.sr.ht/query")
   ;; The authorization and token endpoints, published in
   ;; "https://man.sr.ht/meta.sr.ht/oauth.md".  There is no way to
   ;; autodiscover them from "https://meta.sr.ht/query".
   ("authorization-endpoint" . "https://meta.sr.ht/oauth2/authorize")
   ("access-token-endpoint" . "https://meta.sr.ht/oauth2/access-token")
   ;; The list of features to which Emacs is requesting the server
   ;; grant it access.
   ("scope" . "meta.sr.ht/PROFILE:RO")
   ;; The client secret, which will be generated as part of client
   ;; registration, at
   ;; "https://meta.sr.ht/oauth2/client-registration".  If the user
   ;; generates the client secret, they should note it down.  If the
   ;; Emacs library developer generates it, they should make it
   ;; available to the users of their library somehow.  In either
   ;; case, Emacs will prompt for it, and store it, ideally
   ;; GPG-encrypted, using `auth-source'.  An example client secret
   ;; string is "CeuivTBzZbqJ4iTc+VEdPZJODkBHhuCj4bIqQQAONYaOUGubNM0yG
   ;; ZU3P7ant959W1RkzgvXSeNf2mdxuk5EfA==".  The user would paste this
   ;; 88 character client secret string into the minibuffer when
   ;; prompted.
   ("client-secret-method" . prompt)))

;;;###autoload
(defun url-http-oauth-demo-get-profile-name ()
  "Asynchronously retrieve the Sourcehut profile name.
Print the result to *Messages*.  Return the name."
  (interactive)
  (let ((url-request-method "POST")
        (url-request-extra-headers
         (list (cons "Content-Type" "application/json")))
        (url-request-data
         "{\"query\": \"{ me { canonicalName } }\"}"))
    (with-current-buffer
        (url-retrieve-synchronously
         (url-parse-make-urlobj
          "https"      ; type
          nil          ; user
          nil          ; password, resolved by url-http-oauth
          "meta.sr.ht" ; host
          443          ; port
          "/query"     ; path
          nil nil t))
      (goto-char (point-min))
      (re-search-forward "\n\n")
      (message "%s" (buffer-substring (point) (point-max)))
      (gethash
       "canonicalName"
       (gethash
        "me"
        (gethash
         "data"
         (json-parse-buffer)))))))

(provide 'url-http-oauth-demo)

;;; url-http-oauth-demo.el ends here
