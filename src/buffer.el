(defun orgtrello-buffer/org-entry-put! (point property value)
  (if (or (null value) (string= "" value))
      (orgtrello-buffer/delete-property! property)
    (org-entry-put point property value)))

(defun orgtrello-buffer/back-to-card! ()
  "Given the current position, goes on the card's heading"
  (org-back-to-heading))

(defun orgtrello-buffer/--card-description-start-point! ()
  "Compute the first character of the card's description content."
  (save-excursion (orgtrello-buffer/back-to-card!) (1+ (point-at-eol))))

(defun orgtrello-buffer/--card-start-point! ()
  "Compute the first character of the card."
  (save-excursion (orgtrello-buffer/back-to-card!) (point-at-bol)))

(defun orgtrello-buffer/--card-metadata-end-point! ()
  "Compute the first position of the card's next checkbox."
  (save-excursion
    (orgtrello-buffer/back-to-card!)
    (orgtrello-cbx/--goto-next-checkbox)
    (1- (point))))

(defun orgtrello-buffer/extract-description-from-current-position! ()
  "Given the current position, extract the text content of current card."
  (let ((start (orgtrello-buffer/--card-description-start-point!))
        (end   (orgtrello-buffer/--card-metadata-end-point!)))
    (when (< start end)
          (orgtrello-buffer/filter-out-properties
           (buffer-substring-no-properties start end)))))

(defun orgtrello-buffer/get-card-comments! ()
  "Retrieve the card's comments. Can be nil if not on a card."
  (orgtrello-buffer/org-entry-get (point) *ORGTRELLO-CARD-COMMENTS*))

(defun orgtrello-buffer/put-card-comments! (comments)
  "Retrieve the card's comments. Can be nil if not on a card."
  (orgtrello-buffer/org-entry-put! (point) *ORGTRELLO-CARD-COMMENTS* comments))

(defun orgtrello-buffer/filter-out-properties (text-content)
  "Given a string, remove any org properties if any"
  (->> text-content
       (replace-regexp-in-string "^[ ]*:.*" "")
       (s-trim-left)))

(defun orgtrello-buffer/org-file-get-property! (property-key)
  (assoc-default property-key (orgtrello-buffer/org-file-properties!)))

(defun orgtrello-buffer/board-name! ()
  "Compute the board's name"
  (orgtrello-buffer/org-file-get-property! *BOARD-NAME*))

(defun orgtrello-buffer/board-id! ()
  "Compute the board's id"
  (orgtrello-buffer/org-file-get-property! *BOARD-ID*))

(defun orgtrello-buffer/me! ()
  "Compute the board's current user"
  (orgtrello-buffer/org-file-get-property! *ORGTRELLO-USER-ME*))

(defun orgtrello-buffer/labels! ()
  "Compute the board's current labels and return it as an association list."
  (mapcar (lambda (color) `(,color . ,(orgtrello-buffer/org-file-get-property! color))) '(":red" ":blue" ":orange" ":yellow" ":purple" ":green")))

(defun orgtrello-buffer/pop-up-with-content! (title body-content)
  "Compute a temporary buffer *ORGTRELLO-TITLE-BUFFER-INFORMATION* with the title and body-content."
  (with-temp-buffer-window
   *ORGTRELLO-TITLE-BUFFER-INFORMATION* nil nil
   (progn
     (temp-buffer-resize-mode 1)
     (insert (format "%s:\n\n%s" title body-content)))))

(defun orgtrello-buffer/set-property-comment! (comments)
  "Update comments property."
  (orgtrello-buffer/org-entry-put! nil *ORGTRELLO-CARD-COMMENTS* comments))

(defun orgtrello-buffer/compute-card-metadata-region! ()
  "Compute the card region zone (only the card headers + description) couple '(start end)."
  `(,(orgtrello-buffer/--card-start-point!) ,(orgtrello-buffer/--card-metadata-end-point!)))

(defun orgtrello-buffer/compute-checklist-header-region! ()
  "Compute the checklist's region (only the header, without computing the zone occupied by items) couple '(start end)."
  `(,(point-at-bol) ,(1+ (point-at-eol))))

(defun orgtrello-buffer/compute-checklist-region! ()
  "Compute the checklist's region (including the items) couple '(start end)."
  `(,(point-at-bol) ,(orgtrello-cbx/next-checklist-point!)))

(defun orgtrello-buffer/compute-item-region! ()
  "Compute the item region couple '(start end)."
  `(,(point-at-bol) ,(1+ (point-at-eol))))

(defun orgtrello-buffer/compute-card-region! ()
  "Compute the card region zone (only the card headers + description) couple '(start end)."
  `(,(orgtrello-buffer/--card-start-point!) ,(1- (orgtrello-cbx/compute-next-card-point!))))

(defun orgtrello-buffer/write-item! (item-id entities)
  "Write the item to the org buffer."
  (->> entities
       (gethash item-id)
       (orgtrello-buffer/write-entity! item-id)))

(defun orgtrello-buffer/write-checklist-header! (entity-id entity)
  "Write the checklist data and properties without its structure."
  (orgtrello-buffer/write-entity! entity-id entity))

(defun orgtrello-buffer/write-checklist! (checklist-id entities adjacency)
  "Write the checklist and its structure inside the org buffer."
  (orgtrello-buffer/write-checklist-header! checklist-id (gethash checklist-id entities))
  (--map (orgtrello-buffer/write-item! it entities) (gethash checklist-id adjacency)))

(defun orgtrello-buffer/update-member-ids-property! (entity)
  "Update the users assigned property card entry."
  (--> entity
    (orgtrello-data/entity-member-ids it)
    (orgtrello-buffer/--csv-user-ids-to-csv-user-names it *HMAP-USERS-ID-NAME*)
    (replace-regexp-in-string *ORGTRELLO-USER-PREFIX* "" it)
    (orgtrello-buffer/set-usernames-assigned-property! it)))

(defun orgtrello-buffer/update-property-card-comments! (entity)
  "Update last comments "
  (->> entity
    orgtrello-data/entity-comments
    orgtrello-data/comments-to-list
    orgtrello-buffer/set-property-comment!))

(defun orgtrello-buffer/write-card-header! (card-id card)
  "Given a card entity, write its data and properties without its structure."
  (orgtrello-buffer/write-entity! card-id card)
  (orgtrello-buffer/update-member-ids-property! card)
  (orgtrello-buffer/update-property-card-comments! card)
  (-when-let (card-desc (orgtrello-data/entity-description card))
    (insert (format "%s" card-desc))))

(defun orgtrello-buffer/write-card! (card-id card entities adjacency)
  "Write the card and its structure inside the org buffer."
  (orgtrello-buffer/write-card-header! card-id card)
  (-when-let (checklists (gethash card-id adjacency))
    (insert "\n")
    (--map (orgtrello-buffer/write-checklist! it entities adjacency) checklists)))

(defun orgtrello-buffer/write-entity! (entity-id entity)
  "Write the entity in the buffer to the current position. Move the cursor position."
  (orgtrello-log/msg *OT/INFO* "Synchronizing entity '%s' with id '%s'..." (orgtrello-data/entity-name entity) entity-id)
  (insert (orgtrello-buffer/--compute-entity-to-org-entry entity))
  (when entity-id (orgtrello-buffer/--update-property entity-id (not (orgtrello-data/entity-card-p entity)))))

(defun orgtrello-buffer/overwrite-card-header! (card)
  "Given an updated card 'card' and the current position, overwrite the current position with the updated card data."
  (let ((region (orgtrello-buffer/compute-card-metadata-region!)))
    (apply 'delete-region region)
    (puthash :member-ids (-> card orgtrello-data/entity-member-ids orgtrello-data/--users-to) card)
    (orgtrello-buffer/write-card-header! (orgtrello-data/entity-id card) card)))

(defun orgtrello-buffer/overwrite-card! (card)
  "Given an updated full card 'card' and the current position, overwrite the current position with the full updated card data."
  (let* ((card-id                  (orgtrello-data/entity-id card))
         (region                   (orgtrello-buffer/compute-card-region!))
         (region-start             (first region))
         (region-end               (second region))
         (entities-from-org-buffer (orgtrello-buffer/compute-entities-from-org-buffer! nil region-start region-end))
         (entities-from-trello     (orgtrello-backend/compute-full-cards-from-trello! (list card)))
         (merged-entities          (orgtrello-data/merge-entities-trello-and-org entities-from-trello entities-from-org-buffer))
         (entities                 (first merged-entities))
         (entities-adj             (second merged-entities)))
    (apply 'delete-region region)
    ;; write the full card region with full card structure
    (orgtrello-buffer/write-card! card-id (gethash card-id entities) entities entities-adj)))

(defun orgtrello-buffer/overwrite-checklist-header! (checklist)
  "Given an updated checklist 'checklist' and the current position, overwrite the current position with the updated checklist data."
  (let ((region (orgtrello-buffer/compute-checklist-header-region!)))
    (apply 'orgtrello-cbx/remove-overlays! region)
    (apply 'delete-region region)
    (orgtrello-buffer/write-checklist-header! (orgtrello-data/entity-id checklist) checklist)))

(defun orgtrello-buffer/overwrite-checklist! (checklist)
  "Given an updated full checklist 'checklist' and the current position, overwrite the current position with the full updated checklist data."
  (let* ((region                   (orgtrello-buffer/compute-checklist-region!))
         (region-start             (first region))
         (region-end               (second region))
         (entities-from-org-buffer (orgtrello-buffer/compute-entities-from-org-buffer! nil region-start region-end))
         (entities-from-trello     (orgtrello-backend/compute-full-checklist-from-trello! checklist))
         (merged-entities          (orgtrello-data/merge-entities-trello-and-org entities-from-trello entities-from-org-buffer)))
    (apply 'orgtrello-cbx/remove-overlays! region)
    (apply 'delete-region region)
    ;; write the full checklist region with full checklist structure
    (orgtrello-buffer/write-checklist! (orgtrello-data/entity-id checklist) (first merged-entities) (second merged-entities))))

(defun orgtrello-buffer/overwrite-item! (item)
  "Given an updated item 'item' and the current position, overwrite the current position with the updated item data."
  (let ((region (orgtrello-buffer/compute-item-region!)))
    (apply 'orgtrello-cbx/remove-overlays! region)
    (apply 'delete-region region)
    (orgtrello-buffer/write-entity! (orgtrello-data/entity-id item) (orgtrello-data/merge-item item item)))) ;; hack to merge item to itself to map to the org-trello world, otherwise we lose status for example

(defun orgtrello-buffer/--csv-user-ids-to-csv-user-names (csv-users-id users-id-name)
  "Given a comma separated list of user id and a map, return a comma separated list of username."
  (->> csv-users-id
    orgtrello-data/--users-from
    (--map (gethash it users-id-name))
    orgtrello-data/--users-to))

(defun orgtrello-buffer/--compute-entity-to-org-entry (entity)
  "Given an entity, compute its org representation."
  (funcall
   (cond ((orgtrello-data/entity-card-p entity)      'orgtrello-buffer/--compute-card-to-org-entry)
         ((orgtrello-data/entity-checklist-p entity) 'orgtrello-buffer/--compute-checklist-to-org-entry)
         ((orgtrello-data/entity-item-p entity)      'orgtrello-buffer/--compute-item-to-org-entry))
   entity))

(defun orgtrello-buffer/--compute-due-date (due-date)
  "Compute the format of the due date."
  (if due-date (format "DEADLINE: <%s>\n" due-date) ""))

(defun orgtrello-buffer/--private-compute-card-to-org-entry (name status due-date tags)
  "Compute the org format for card."
  (let ((prefix-string (format "* %s %s" (if status status *TODO*) name)))
    (format "%s%s\n%s" prefix-string (orgtrello-buffer/--serialize-tags prefix-string tags) (orgtrello-buffer/--compute-due-date due-date))))

(defun orgtrello-buffer/--serialize-tags (prefix-string tags)
  "Compute the tags serialization string. If tags is empty, return \"\", otherwise, if prefix-string's length is superior to 72, only  "
  (if (or (null tags) (string= "" tags))
      ""
    (let ((l (length prefix-string)))
      (format "%s%s" (if (< 72 l) " " (orgtrello-buffer/--symbol " " (- 72 l))) tags))))

(defun orgtrello-buffer/--compute-card-to-org-entry (card)
  "Given a card, compute its org-mode entry equivalence. orgcheckbox-p is nil"
  (orgtrello-buffer/--private-compute-card-to-org-entry
   (orgtrello-data/entity-name card)
   (orgtrello-data/entity-keyword card)
   (orgtrello-data/entity-due card)
   (orgtrello-data/entity-tags card)))

(defun orgtrello-buffer/--compute-checklist-to-orgtrello-entry (name &optional level status)
  "Compute the orgtrello format checklist"
  (format "** %s\n" name))

(defun orgtrello-buffer/--symbol (sym n)
  "Compute the repetition of a symbol as a string"
  (--> n
       (-repeat it sym)
       (s-join "" it)))

(defun orgtrello-buffer/--space (n)
  "Given a level, compute the number of space for an org checkbox entry."
  (orgtrello-buffer/--symbol " "  n))

(defun orgtrello-buffer/--star (n)
  "Given a level, compute the number of space for an org checkbox entry."
  (orgtrello-buffer/--symbol "*"  n))

(defun orgtrello-buffer/--compute-state-checkbox (state)
  "Compute the status of the checkbox"
  (orgtrello-data/--compute-state-generic state '("[X]" "[-]")))

(defun orgtrello-buffer/--compute-level-into-spaces (level)
  "level 2 is 0 space, otherwise 2 spaces."
  (if (equal level *CHECKLIST-LEVEL*) 0 2))

(defun orgtrello-buffer/--compute-checklist-to-org-checkbox (name &optional level status)
  "Compute checklist to the org checkbox format"
  (format "%s- %s %s\n"
          (-> level
              orgtrello-buffer/--compute-level-into-spaces
              orgtrello-buffer/--space)
          (orgtrello-buffer/--compute-state-checkbox status)
          name))

(defun orgtrello-buffer/--compute-item-to-org-checkbox (name &optional level status)
  "Compute item to the org checkbox format"
  (format "%s- %s %s\n"
          (-> level
              orgtrello-buffer/--compute-level-into-spaces
              orgtrello-buffer/--space)
          (orgtrello-data/--compute-state-item-checkbox status)
          name))

(defun orgtrello-buffer/--compute-checklist-to-org-entry (checklist &optional orgcheckbox-p)
  "Given a checklist, compute its org-mode entry equivalence."
  (orgtrello-buffer/--compute-checklist-to-org-checkbox (orgtrello-data/entity-name checklist) *CHECKLIST-LEVEL* "incomplete"))

(defun orgtrello-buffer/--compute-item-to-org-entry (item)
  "Given a checklist item, compute its org-mode entry equivalence."
  (orgtrello-buffer/--compute-item-to-org-checkbox (orgtrello-data/entity-name item) *ITEM-LEVEL* (orgtrello-data/entity-keyword item)))

(defun orgtrello-buffer/--put-card-with-adjacency (current-meta entities adjacency)
  "Deal with adding card to entities."
  (-> current-meta
      (orgtrello-buffer/--put-entities entities)
      (list adjacency)))

(defun orgtrello-buffer/--dispatch-create-entities-map-with-adjacency (entity)
  "Dispatch the function to update map depending on the entity level."
  (if (orgtrello-data/entity-card-p entity) 'orgtrello-buffer/--put-card-with-adjacency 'orgtrello-backend/--put-entities-with-adjacency))

(defun orgtrello-buffer/--compute-entities-from-org! (&optional region-end)
  "Compute the full entities present in the org buffer which already had been sync'ed previously. Return the list of entities map and adjacency map in this order. If region-end is specified, will work on the region (current-point, region-end), otherwise, work on all buffer."
  (let ((entities (orgtrello-hash/empty-hash))
        (adjacency (orgtrello-hash/empty-hash)))
    (orgtrello-buffer/org-map-entities-without-params!
     (lambda ()
       ;; either the region-end is null, so we work on all the buffer, or the region-end is specified and we need to filter out entities that are after the specified point.
       (when (or (null region-end) (< (point) region-end))
         ;; first will unfold every entries, otherwise https://github.com/org-trello/org-trello/issues/53
         (org-show-subtree)
         (let ((current-entity (-> (orgtrello-buffer/entry-get-full-metadata!) orgtrello-data/current)))
           (unless (-> current-entity orgtrello-data/entity-id orgtrello-data/id-p) ;; if no id, we set one
             (orgtrello-buffer/--set-marker (orgtrello-buffer/--compute-marker-from-entry current-entity)))
           (let ((current-meta (orgtrello-buffer/entry-get-full-metadata!)))
             (-> current-meta ;; we recompute the metadata because they may have changed
               orgtrello-data/current
               orgtrello-buffer/--dispatch-create-entities-map-with-adjacency
               (funcall current-meta entities adjacency)))))))
    (list entities adjacency)))

;; entities of the form: {entity-id '(entity-card {checklist-id (checklist (item))})}

(defun orgtrello-buffer/compute-entities-from-org-buffer! (&optional buffername region-start region-end)
  "Compute the current entities hash from the buffer in the same format as the sync-from-trello routine. Return the list of entities map and adjacency map in this order."
  (when buffername
    (set-buffer buffername))
  (save-excursion
    (goto-char (if region-start region-start (point-min))) ;; start from start-region if specified, otherwise, start from the start of the file
    (orgtrello-buffer/--compute-entities-from-org! region-end)))

(defun orgtrello-buffer/--put-entities (current-meta entities)
  "Deal with adding a new item to entities."
  (-> current-meta
      orgtrello-data/current
      (orgtrello-backend/--add-entity-to-entities entities)))

(defun orgtrello-buffer/--update-property (id orgcheckbox-p)
  "Update the property depending on the nature of thing to sync. Move the cursor position."
  (if orgcheckbox-p
      (save-excursion
        (forward-line -1) ;; need to get back one line backward for the checkboxes as their properties is at the same level (otherwise, for headings we do not care)
        (orgtrello-buffer/set-property *ORGTRELLO-ID* id))
      (orgtrello-buffer/set-property *ORGTRELLO-ID* id)))

(defun orgtrello-buffer/--set-marker (marker)
  "Set a marker to get back to later."
  (orgtrello-buffer/set-property *ORGTRELLO-ID* marker))

(defun orgtrello-buffer/set-marker-if-not-present (current-entity marker)
  "Set the marker to the entry if we never did."
  (unless (string= (orgtrello-data/entity-id current-entity) marker) ;; if never created before, we need a marker to add inside the file
    (orgtrello-buffer/--set-marker marker)))

(defun orgtrello-buffer/org-map-entities-without-params! (fn-to-execute)
  "Execute fn-to-execute function for all entities from buffer - fn-to-execute is a function without any parameters."
  (org-map-entries
   (lambda ()
     (funcall fn-to-execute) ;; execute on heading entry
     (orgtrello-cbx/map-checkboxes fn-to-execute)) t 'file))

(defun orgtrello-buffer/get-usernames-assigned-property! ()
  "Read the org users property from the current entry."
  (org-entry-get nil *ORGTRELLO-USERS-ENTRY*))

(defun orgtrello-buffer/set-usernames-assigned-property! (csv-users)
  "Update users org property."
  (orgtrello-buffer/org-entry-put! nil *ORGTRELLO-USERS-ENTRY* csv-users))

(defun orgtrello-buffer/delete-property! (property)
  "Given a property name (checkbox), if found, delete it from the buffer."
  (org-delete-property-globally property)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward ":PROPERTIES: {.*" nil t)
      (remove-overlays (point-at-bol) (point-at-eol)) ;; the current overlay on this line
      (replace-match "" nil t))))                     ;; then remove the property

(defun orgtrello-buffer/remove-overlays! ()
  "Remove every org-trello overlays from the current buffer."
  (orgtrello-cbx/remove-overlays! (point-min) (point-max)))

(defun orgtrello-buffer/install-overlays! ()
  "Install overlays throughout the all buffers."
  (orgtrello-buffer/remove-overlays!)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward ":PROPERTIES: {.*" nil t)
      (orgtrello-cbx/install-overlays! (match-beginning 0)))))


(defun orgtrello-buffer/--convert-orgmode-date-to-trello-date (orgmode-date)
  "Convert the org-mode deadline into a time adapted for trello."
  (if (and orgmode-date (not (string-match-p "T*Z" orgmode-date)))
      (cl-destructuring-bind (sec min hour day mon year dow dst tz)
                             (--map (if it (if (< it 10) (concat "0" (int-to-string it)) (int-to-string it)))
                                    (parse-time-string orgmode-date))
        (concat (concat year "-" mon "-" day "T") (if hour (concat hour ":" min ":" sec) "00:00:00") ".000Z"))
      orgmode-date))

(defun orgtrello-buffer/org-entity-metadata! ()
  "Compute the metadata the org-mode way."
  (org-heading-components))

(defun orgtrello-buffer/--extract-metadata! ()
  "Extract the current metadata depending on the org-trello's checklist policy."
  (funcall (if (orgtrello-cbx/checkbox-p) 'orgtrello-cbx/org-checkbox-metadata! 'orgtrello-buffer/org-entity-metadata!)))

(defun orgtrello-buffer/extract-identifier! (point)
  "Extract the identifier from the point."
  (orgtrello-buffer/org-entry-get point *ORGTRELLO-ID*))

(defun orgtrello-buffer/set-property (key value)
  "Either set the propery normally (as for entities) or specifically for checklist."
  (funcall (if (orgtrello-cbx/checkbox-p) 'orgtrello-cbx/org-set-property 'org-set-property) key value))

(defun orgtrello-buffer/org-entry-get (point key)
  "Extract the identifier from the point."
  (funcall (if (orgtrello-cbx/checkbox-p) 'orgtrello-cbx/org-get-property 'org-entry-get) point key))

(defun orgtrello-buffer/metadata! ()
  "Compute the metadata for a given org entry. Also add some metadata identifier/due-data/point/buffer-name/etc..."
  (let ((current-point (point)))
    (->> (orgtrello-buffer/--extract-metadata!)
         (cons (-> current-point (orgtrello-buffer/org-entry-get "DEADLINE") orgtrello-buffer/--convert-orgmode-date-to-trello-date))
         (cons (orgtrello-buffer/extract-identifier! current-point))
         (cons current-point)
         (cons (buffer-name))
         (cons (orgtrello-buffer/--user-ids-assigned-to-current-card))
         (cons (orgtrello-buffer/extract-description-from-current-position!))
         (cons (orgtrello-buffer/org-entry-get current-point *ORGTRELLO-CARD-COMMENTS*))
         orgtrello-buffer/--convert-to-orgtrello-metadata)))

(defun orgtrello-buffer/org-up-parent! ()
  "A function to get back to the current entry's parent"
  (funcall (if (orgtrello-cbx/checkbox-p) 'orgtrello-cbx/org-up! 'org-up-heading-safe)))

(defun orgtrello-buffer/--parent-metadata! ()
  "Extract the metadata from the current heading's parent."
  (save-excursion
    (orgtrello-buffer/org-up-parent!)
    (orgtrello-buffer/metadata!)))

(defun orgtrello-buffer/--grandparent-metadata! ()
  "Extract the metadata from the current heading's grandparent."
  (save-excursion
    (orgtrello-buffer/org-up-parent!)
    (orgtrello-buffer/org-up-parent!)
    (orgtrello-buffer/metadata!)))

(defun orgtrello-buffer/entry-get-full-metadata! ()
  "Compute metadata needed for entry into a map with keys :current, :parent, :grandparent. Returns nil if the level is superior to 4."
  (let* ((current   (orgtrello-buffer/metadata!))
         (level     (orgtrello-data/entity-level current)))
    (when (< level *OUTOFBOUNDS-LEVEL*)
          (let ((ancestors (cond ((= level *CARD-LEVEL*)      '(nil nil))
                                 ((= level *CHECKLIST-LEVEL*) `(,(orgtrello-buffer/--parent-metadata!) nil))
                                 ((= level *ITEM-LEVEL*)      `(,(orgtrello-buffer/--parent-metadata!) ,(orgtrello-buffer/--grandparent-metadata!))))))
            (orgtrello-hash/make-hierarchy current (first ancestors) (second ancestors))))))

(defun orgtrello-buffer/--convert-to-orgtrello-metadata (heading-metadata)
  "Given the heading-metadata returned by the function 'org-heading-components, make it a hashmap with key :level, :keyword, :name. and their respective value"
  (cl-destructuring-bind (comments description member-ids buffer-name point id due level _ keyword _ name tags) heading-metadata
                         (orgtrello-hash/make-hash-org member-ids level keyword name id due point buffer-name description comments tags)))

(defun orgtrello-buffer/current-level! ()
  "Compute the current level's position."
  (-> (orgtrello-buffer/metadata!) orgtrello-data/entity-level))

(defun orgtrello-buffer/filtered-kwds! ()
  "org keywords used (based on org-todo-keywords-1)."
  org-todo-keywords-1)

(defun orgtrello-buffer/org-file-properties! ()
  org-file-properties)

(defun orgtrello-buffer/org-map-entries (level fn-to-execute)
  "Map fn-to-execute to a given entities with level level. fn-to-execute is a function without any parameter."
  (org-map-entries (lambda () (when (= level (orgtrello-buffer/current-level!)) (funcall fn-to-execute)))))

(orgtrello-log/msg *OT/DEBUG* "org-trello - orgtrello-buffer loaded!")


