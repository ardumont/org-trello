;;; org-trello.el --- Minor mode to synchronize org-mode buffer and trello board

;; Copyright (C) 2013 Antoine R. Dumont <eniotna.t AT gmail.com>

;; Author: Antoine R. Dumont <eniotna.t AT gmail.com>
;; Maintainer: Antoine R. Dumont <eniotna.t AT gmail.com>
;; Version: 0.5.2
;; Package-Requires: ((dash "2.8.0") (request "0.2.0") (s "1.9.0") (concurrent "0.3.2"))
;; Keywords: org-mode trello sync org-trello
;; URL: https://github.com/org-trello/org-trello

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Minor mode to sync org-mode buffer and trello board
;;
;; 1) Add the following to your Emacs init file
;; (require 'org-trello)
;; (add-hook 'org-mode-hook 'org-trello-mode)
;;
;; 2) Once - Install the consumer-key and read/write token for org-trello to work in your name with your boards (C-c o i)
;; M-x org-trello/install-key-and-token
;;
;; You may want:
;; - to connect your org buffer to an existing board (C-c o I).  Beware that this will only install properties needed to speak with trello board (nothing else).
;; M-x org-trello/install-board-and-lists-ids
;;
;; - to create an empty board directly from a org-mode buffer (C-c o b)
;; M-x org-trello/create-board
;;
;; 3) Now check your setup is ok (C-c o d)
;; M-x org-trello/check-setup
;;
;; 6) For some more help (C-c o h)
;; M-x org-trello/help-describing-setup
;;
;; 7) If you attached to an existing trello board, you may want to bootstrap your org-buffer (C-u C-c o s)
;; C-u M-x org-trello/sync-buffer
;;
;; Now you can work with trello from the comfort of org-mode and Emacs
;;
;; 8) Sync a card from Org to Trello (C-c o c/C-c o C)
;; M-x org-trello/sync-card
;;
;; 9) Sync a card from Trello to Org (C-u C-c o c/C-u C-c o C)
;; C-u M-x org-trello/sync-card
;;
;; 10) Sync all the org buffer to trello (C-c o s)
;; M-x org-trello/sync-buffer
;;
;; 11) As already mentioned, you can sync all the org buffer from trello (C-u C-c o s)
;; C-u M-x org-trello/sync-buffer
;;
;; Enjoy!
;;
;; More informations on https://org-trello.github.io/org-trello

;;; Code:

(defconst *ORGTRELLO/ERROR-INSTALL-MSG* (format "Oops - your Emacs isn't supported. org-trello only works on Emacs 24.3+ and you're running version: %s.
Please consider upgrading Emacs." emacs-version) "Error message when installing org-trello with an unsupported Emacs version.")

(when (version< emacs-version "24") (error *ORGTRELLO/ERROR-INSTALL-MSG*))

;; Dependency on internal Emacs libs
(require 'org)
(require 'json)
(require 'parse-time)
(require 'timer)
(require 'align)
(require 'deferred)

;; Dependency on external Emacs libs
(require 'dash)
(require 'request)
(require 's)

(defconst *ORGTRELLO/VERSION* "0.5.2" "Current org-trello version installed.")



(require 'org-trello-log)
(require 'org-trello-utils)
(require 'org-trello-setup)
(require 'org-trello-action)
(require 'org-trello-controller)
(require 'org-trello-buffer)

(org-trello/require-cl)



(defun org-trello/version ()
  "Org-trello version."
  (interactive)
  (orgtrello-log/msg *OT/NOLOG* "version: %s" *ORGTRELLO/VERSION*))



(defun org-trello/apply-with-deferred (comp &optional current-buffer-to-save reload-org-setup nolog-p)
  "Apply org-trello COMP which returns deferred computations.
When CURRENT-BUFFER-TO-SAVE (buffer name) is provided, save such buffer.
When RELOAD-ORG-SETUP is provided, reload the org setup.
when NOLOG-P is specified, no output log."
  (let ((deferred-fns (with-local-quit
                        (save-excursion
                          (apply (car comp) (cdr comp))))))
    (--> deferred-fns
      (cons 'deferred:$ it)
      (-snoc it '(deferred:error it
                   (lambda (x) (orgtrello-log/msg *OT/ERROR* "Problem during execution - '%s'!" x))))
      (-snoc it `(deferred:nextc it
                   (lambda ()
                     (when ,current-buffer-to-save (with-current-buffer ,current-buffer-to-save
                                                      (call-interactively 'save-buffer)))
                     (when ,reload-org-setup (orgtrello-action/reload-setup!))
                     (unless ,nolog-p (orgtrello-log/msg *OT/INFO* "Done!")))))
      (eval it))))

(defun org-trello/apply (comp &optional current-buffer-to-save reload-org-setup nolog-p)
  "Apply org-trello computation COMP.
When CURRENT-BUFFER-TO-SAVE (buffer name) is provided, save such buffer.
When RELOAD-ORG-SETUP is provided, reload the org setup.
when NOLOG-P is specified, no output log."
  (lexical-let ((computation    comp)
                (buffer-to-save current-buffer-to-save)
                (reload-setup   reload-org-setup)
                (nolog-flag     nolog-p))
    (deferred:$
      (deferred:next
        (lambda () (save-excursion
                     (with-local-quit
                       (apply (car computation) (cdr computation))))))
      (deferred:error it
        (lambda (x) (orgtrello-log/msg *OT/ERROR* "Problem during execution - '%s'!" x)))
      (deferred:nextc it
        (lambda ()
          (when buffer-to-save (with-current-buffer buffer-to-save
                                 (call-interactively 'save-buffer)))
          (when reload-setup (orgtrello-action/reload-setup!))
          (unless nolog-flag (orgtrello-log/msg *OT/INFO* "Done!")))))))

(defun org-trello/log-strict-checks-and-do (action-label action-fn &optional with-save-flag)
  "Given an ACTION-LABEL and an ACTION-FN, execute sync action.
If WITH-SAVE-FLAG is set, will do a buffer save and reload the org setup."
  (orgtrello-action/msg-controls-or-actions-then-do
   action-label
   '(orgtrello-controller/load-keys!
     orgtrello-controller/control-keys!
     orgtrello-controller/setup-properties!
     orgtrello-controller/control-properties!
     orgtrello-controller/control-encoding!)
   action-fn))

(defun org-trello/log-light-checks-and-do (action-label action-fn &optional no-check-flag)
  "Given an ACTION-LABEL and an ACTION-FN, execute sync action.
If NO-CHECK-FLAG is set, no controls are done."
  (orgtrello-action/msg-controls-or-actions-then-do
   action-label
   (if no-check-flag nil '(orgtrello-controller/load-keys! orgtrello-controller/control-keys! orgtrello-controller/setup-properties!))
   action-fn))

(defun org-trello/abort-sync ()
  "Control first, then if ok, add a comment to the current card."
  (interactive)
  (deferred:clear-queue))

(defun org-trello/add-card-comments ()
  "Control first, then if ok, add a comment to the current card."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Add card comment" orgtrello-controller/do-add-card-comment!)))

(defun org-trello/show-card-comments ()
  "Control first, then if ok, show a simple buffer with the current card's last comments."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Display current card's last comments" orgtrello-controller/do-show-card-comments!)))

(defun org-trello/show-board-labels ()
  "Control first, then if ok, show a simple buffer with the current board's labels."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Display current board's labels" orgtrello-controller/do-show-board-labels!)))

(defun org-trello/sync-card (&optional modifier)
  "Execute the sync of an entity and its structure to trello.
If MODIFIER is non nil, execute the sync entity and its structure from trello."
  (interactive "P")
  (if modifier
      (org-trello/apply '(org-trello/log-strict-checks-and-do "Request 'sync entity with structure from trello" orgtrello-controller/do-sync-card-from-trello!) (current-buffer))
    (org-trello/apply-with-deferred '(org-trello/log-strict-checks-and-do "Request 'sync entity with structure to trello" orgtrello-controller/do-sync-card-to-trello!) (current-buffer))))

(defun org-trello/sync-buffer (&optional modifier)
  "Execute the sync of the entire buffer to trello.
If MODIFIER is non nil, execute the sync of the entire buffer from trello."
  (interactive "P")
  (org-trello/apply (cons 'org-trello/log-strict-checks-and-do
                          (if modifier
                              '("Request 'sync org buffer from trello board'" orgtrello-controller/do-sync-full-file-from-trello!)
                            '("Request 'sync org buffer to trello board'" orgtrello-controller/do-sync-full-file-to-trello!)))
                    (current-buffer)))

(defun org-trello/kill-entity (&optional modifier)
  "Execute the entity removal from trello and the buffer.
If MODIFIER is non nil, execute all entities removal from trello and buffer."
  (interactive "P")
  (org-trello/apply (cons 'org-trello/log-strict-checks-and-do
                          (if modifier
                              '("Request - 'delete entities'" orgtrello-controller/do-delete-entities)
                            '("Request 'delete entity'" orgtrello-controller/do-delete-simple)))
                    (current-buffer)))

(defun org-trello/kill-cards ()
  "Execute all entities removal from trello and buffer."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Request - 'delete entities'" orgtrello-controller/do-delete-entities) (current-buffer)))

(defun org-trello/install-key-and-token ()
  "No control, trigger the setup installation of the key and the read/write token."
  (interactive)
  (org-trello/apply '(org-trello/log-light-checks-and-do "Setup key and token" orgtrello-controller/do-install-key-and-token 'do-no-checks)))

(defun org-trello/install-board-and-lists-ids ()
  "Control first, then if ok, trigger the setup installation of the trello board to sync with."
  (interactive)
  (org-trello/apply '(org-trello/log-light-checks-and-do "Install boards and lists" orgtrello-controller/do-install-board-and-lists) (current-buffer) 'reload-setup))

(defun org-trello/update-board-metadata ()
  "Control first, then if ok, trigger the update of the informations about the board."
  (interactive)
  (org-trello/apply '(org-trello/log-light-checks-and-do "Update board information" orgtrello-controller/do-update-board-metadata!) (current-buffer) 'reload-setup))

(defun org-trello/jump-to-card (&optional modifier)
  "Jump from current card to trello card in browser.
If MODIFIER is not nil, jump from current card to board."
  (interactive "P")
  (org-trello/apply (cons 'org-trello/log-strict-checks-and-do
                          (if modifier
                              '("Jump to board" orgtrello-controller/jump-to-board!)
                            '("Jump to card" orgtrello-controller/jump-to-card!)))
                    nil nil 'no-log))

(defun org-trello/jump-to-trello-board ()
  "Jump to current trello board."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Jump to board" orgtrello-controller/jump-to-board!) nil nil 'no-log))

(defun org-trello/create-board ()
  "Control first, then if ok, trigger the board creation."
  (interactive)
  (org-trello/apply '(org-trello/log-light-checks-and-do "Create board and lists" orgtrello-controller/do-create-board-and-lists) (current-buffer) 'reload-setup))

(defun org-trello/assign-me (&optional modifier)
  "Assign oneself to the card.
If MODIFIER is not nil, unassign oneself from the card."
  (interactive "P")
  (org-trello/apply (cons 'org-trello/log-light-checks-and-do
                          (if modifier
                              '("Unassign me from card" orgtrello-controller/do-unassign-me)
                            '("Assign myself to card" orgtrello-controller/do-assign-me)))
                    (current-buffer)))

(defun org-trello/check-setup ()
  "Check the current setup."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Checking setup." (lambda () (orgtrello-log/msg *OT/NOLOG* "Setup ok!"))) nil nil 'no-log))

(defun org-trello/delete-setup ()
  "Delete the current setup."
  (interactive)
  (org-trello/apply '(org-trello/log-strict-checks-and-do "Delete current org-trello setup" orgtrello-controller/delete-setup!) (current-buffer)))

(defun org-trello/help-describing-bindings ()
  "A simple message to describe the standard bindings used."
  (interactive)
  (org-trello/apply `(message ,(org-trello/--help-describing-bindings-template *ORGTRELLO/MODE-PREFIX-KEYBINDING* *org-trello-interactive-command-binding-couples*)) nil nil 'no-log))

;;;;;; End interactive commands

(defun org-trello/--startup-message (prefix-keybinding)
  "Compute org-trello's startup message with the PREFIX-KEYBINDING."
  (orgtrello-utils/replace-in-string "#PREFIX#" prefix-keybinding "org-trello/ot is on! To begin with, hit #PREFIX# h or M-x 'org-trello/help-describing-bindings"))

(defun org-trello/--help-describing-bindings-template (keybinding list-command-binding-description)
  "Standard Help message template from KEYBINDING and LIST-COMMAND-BINDING-DESCRIPTION."
  (->> list-command-binding-description
    (--map (let ((command        (car it))
                 (prefix-binding (cadr it))
                 (help-msg       (cadr (cdr it))))
             (concat keybinding " " prefix-binding " - M-x " (symbol-name command) " - " help-msg)))
    (s-join "\n")))

(defun org-trello/--install-local-keybinding-map! (previous-org-trello-mode-prefix-keybinding org-trello-mode-prefix-keybinding interactive-command-binding-to-install)
  "Install locally the default binding map with the prefix binding of org-trello-mode-prefix-keybinding."
  (mapc (lambda (command-and-binding)
          (let ((command (car command-and-binding))
                (binding (cadr command-and-binding)))
            ;; unset previous binding
            (define-key org-trello-mode-map (kbd (concat previous-org-trello-mode-prefix-keybinding binding)) nil)
            ;; set new binding
            (define-key org-trello-mode-map (kbd (concat org-trello-mode-prefix-keybinding binding)) command)))
        interactive-command-binding-to-install))

(defun org-trello/--remove-local-keybinding-map! (previous-org-trello-mode-prefix-keybinding interactive-command-binding-to-install)
  "Remove the default org-trello bindings."
  (mapc (lambda (command-and-binding)
          (let ((command (car command-and-binding))
                (binding (cadr command-and-binding)))
            (define-key org-trello-mode-map (kbd (concat previous-org-trello-mode-prefix-keybinding binding)) nil)))
        interactive-command-binding-to-install))

(defun org-trello/install-local-prefix-mode-keybinding! (keybinding)
  "Install the new default org-trello mode keybinding."
  (setq *PREVIOUS-ORGTRELLO/MODE-PREFIX-KEYBINDING* *ORGTRELLO/MODE-PREFIX-KEYBINDING*)
  (setq *ORGTRELLO/MODE-PREFIX-KEYBINDING* keybinding)
  (org-trello/--install-local-keybinding-map! *PREVIOUS-ORGTRELLO/MODE-PREFIX-KEYBINDING* *ORGTRELLO/MODE-PREFIX-KEYBINDING* *org-trello-interactive-command-binding-couples*))

(defun org-trello/remove-local-prefix-mode-keybinding! (keybinding)
  "Install the new default org-trello mode keybinding."
  (org-trello/--remove-local-keybinding-map! *PREVIOUS-ORGTRELLO/MODE-PREFIX-KEYBINDING* *org-trello-interactive-command-binding-couples*))

;;;###autoload
(define-minor-mode org-trello-mode "Sync your org-mode and your trello together."
  :lighter " ot"
  :keymap org-trello-mode-map)

(defvar org-trello-mode-hook '()
  "Define one org-trello hook for user to extend org-trello with their own behavior.")

(add-hook 'org-trello-mode-on-hook 'orgtrello-controller/mode-on-hook-fn)

(add-hook 'org-trello-mode-on-hook (lambda ()
                                     ;; install the bindings
                                     (org-trello/install-local-prefix-mode-keybinding! *ORGTRELLO/MODE-PREFIX-KEYBINDING*)
                                     ;; Overwrite the org-mode-map
                                     (define-key org-trello-mode-map [remap org-end-of-line] 'orgtrello-buffer/end-of-line!)
                                     (define-key org-trello-mode-map [remap org-return] 'orgtrello-buffer/org-return!)
                                     (define-key org-trello-mode-map [remap org-ctrl-c-ret] 'orgtrello-buffer/org-ctrl-c-ret!)
                                     ;; a little message in the minibuffer to notify the user
                                     (orgtrello-log/msg *OT/NOLOG* (org-trello/--startup-message *ORGTRELLO/MODE-PREFIX-KEYBINDING*)))
          'do-append)

(add-hook 'org-trello-mode-off-hook 'orgtrello-controller/mode-off-hook-fn)

(add-hook 'org-trello-mode-off-hook (lambda ()
                                      ;; remove the bindings when org-trello mode off
                                      (org-trello/remove-local-prefix-mode-keybinding! *ORGTRELLO/MODE-PREFIX-KEYBINDING*)
                                      ;; remove mapping override
                                      (define-key org-trello-mode-map [remap org-end-of-line] nil)
                                      (define-key org-trello-mode-map [remap org-return] nil)
                                      (define-key org-trello-mode-map [remap org-ctrl-c-ret] nil)
                                      ;; a little message in the minibuffer to notify the user
                                      (orgtrello-log/msg *OT/NOLOG* "org-trello/ot is off!"))
          'do-append)

(orgtrello-log/msg *OT/DEBUG* "org-trello loaded!")

(provide 'org-trello)
;;; org-trello.el ends here
