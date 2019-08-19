;;; org-timeline.el --- Add graphical view of agenda to agenda buffer. -*- lexical-binding: t -*-

;; Copyright (C) 2017 Matúš Goljer

;; Author: Matúš Goljer <matus.goljer@gmail.com>
;; Maintainer: Matúš Goljer <matus.goljer@gmail.com>
;; Version: 0.3.0
;; Created: 16th April 2017
;; Package-requires: ((dash "2.13.0") (emacs "24.3"))
;; Keywords: calendar
;; URL: https://github.com/Fuco1/org-timeline/

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Add graphical view of agenda to agenda buffer.

;; This package adds a graphical view of the agenda after the last
;; agenda line.  By default the display starts at 5 AM today and
;; goes up to 4 AM next day (this covers 24 hours).

;; Scheduled tasks or tasks with time ranges are rendered in the
;; display with `org-timeline-block' face.  Clocked entires are
;; displayed in `org-timeline-clocked' face.  The background of
;; timeslots which are in the past is highlighted with
;; `org-timeline-elapsed' face.

;; You can use custom color for a task by adding the property
;; `TIMELINE_FACE' with either a string which is a color name or a
;; list which specifies the face properties or a symbol which is
;; taken to be a face name.

;;; Code:

(require 'dash)

(require 'org-agenda)

(defgroup org-timeline ()
  "Graphical view of agenda in agenda buffer."
  :group 'org
  :prefix "org-timeline-")

(defgroup org-timeline-faces ()
  "Faces for org-timeline."
  :group 'org-timeline)

(defface org-timeline-block
  '((t (:background "CadetBlue")))
  "Face used for printing blocks with time range information.

These are blocks that are scheduled for specific time range or
have an active timestamp with a range."
  :group 'org-timeline-faces)

(defface org-timeline-conflict
  '((t (:background "OrangeRed")))
  "Face used for printing conflicting blocks with time range information."
  :group 'org-timeline-faces)

(defface org-timeline-elapsed
  '((t (:inherit region)))
  "Face used for highlighting elapsed portion of the day."
  :group 'org-timeline-faces)

(defface org-timeline-clocked
  '((t (:background "DarkOliveGreen")))
  "Face used for printing clocked blocks.

Clocked blocks appear in the agenda when `org-agenda-log-mode' is
activated."
  :group 'org-timeline-faces)

(defcustom org-timeline-default-duration
  nil
  "Default event duration for org-timeline")

(defmacro org-timeline-with-each-line (&rest body)
  "Execute BODY on each line in buffer."
  (declare (indent 0)
           (debug (body)))
  `(save-excursion
     (goto-char (point-min))
     ,@body
     (while (= (forward-line) 0)
       ,@body)))

(defun org-timeline--get-face ()
  "Get the face with which to draw the current block."
  (--if-let (org-entry-get (org-get-at-bol 'org-marker) "TIMELINE_FACE" t)
      (let ((read-face (car (read-from-string it))))
        (if (stringp read-face)
            (list :background read-face)
          read-face))
    (cond
     ((save-excursion
        (search-forward "Clocked:" (line-end-position) t))
      'org-timeline-clocked)
     ((face-at-point)
      `((:background ,(face-attribute (face-at-point) ':foreground nil 'default))))
     (t 'org-timeline-block))))

(defun org-timeline--add-elapsed-face (string current-offset)
  "Add `org-timeline-elapsed' to STRING's elapsed portion.

Return new copy of STRING."
  (let ((string-copy (copy-sequence string)))
    (when (< 0 current-offset)
      (put-text-property 0 current-offset 'font-lock-face 'org-timeline-elapsed string-copy))
    string-copy))

(defun org-timeline--generate-timeline ()
  "Generate the timeline string that will represent current agenda view."
  (let* ((start-offset 270)
         (current-time (+ (* 60 (string-to-number (format-time-string "%H")))
                          (string-to-number (format-time-string "%M"))))
         (current-offset (/ (- current-time start-offset) 10))
         (slotline (org-timeline--add-elapsed-face
                    "|     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |"
                    current-offset))
         (hourline (org-timeline--add-elapsed-face
                    "   |05:00|06:00|07:00|08:00|09:00|10:00|11:00|12:00|13:00|14:00|15:00|16:00|17:00|18:00|19:00|20:00|21:00|22:00|23:00|00:00|01:00|02:00|03:00|04:00|"
                    current-offset))
;         (timeline (concat hourline "\n" slotline))
         (tasks nil))
    (org-timeline-with-each-line
      (-when-let* ((time-of-day (org-get-at-bol 'time-of-day))
                   (marker (org-get-at-bol 'org-marker))
                   (type (org-get-at-bol 'type))
		   (name (org-get-at-bol 'txt)))
        (when (member type (list "scheduled" "clock" "timestamp"))
          (let ((duration (or (org-get-at-bol 'duration)
			      org-timeline-default-duration
			      0)))
            (when (and (numberp duration)            
                       (< duration 0))            ;; This is events at midnight
              (cl-incf duration 1440))

            (let* ((hour (/ time-of-day 100))     ;; time-of-day is in HHMM notation
                   (minute (mod time-of-day 100))
		   (day-of-month (calendar-absolute-from-gregorian (org-get-at-bol 'date)))
                   (beg (+ (* day-of-month 1440) (* hour 60) minute))
                   (end (round (+ beg duration)))
                   (face (org-timeline--get-face)))
	      (push (list beg end face name) tasks))))))

    (setq tasks (nreverse tasks))
    (cl-labels ((get-start-pos (current-line beg) (+ 1 (* current-line (1+ (length hourline))) (/ (- beg start-offset) 10)))
                (get-end-pos (current-line end) (+ 1 (* current-line (1+ (length hourline))) (/ (- end start-offset) 10))))
      (let ((current-line 1)
	    (current-day nil))
        (with-temp-buffer
          (insert hourline)
          (-each tasks
            (-lambda ((beg end face name))
	      (let ((new-current-day (/ beg 1440))
		    (beg-in-day (% beg 1440))
		    (end-in-day (% end 1440)))
		(when (not current-day)
		  (setq current-day new-current-day)
		  (insert "\n" (calendar-day-name (mod current-day 7) t t) slotline))
		(while (< current-day new-current-day)               ;; We have advanced a day
		  (cl-incf current-line)
		  (cl-incf current-day)
		  (save-excursion
                    (goto-char (point-max))
                    (insert "\n" (calendar-day-name (mod current-day 7) t t) slotline)))
		(let ((start-pos (get-start-pos current-line beg-in-day))
		      (end-pos (get-end-pos current-line end-in-day)))
		  (if (or (get-text-property (get-start-pos current-line beg-in-day) 'org-timeline-occupied)
			  (get-text-property (get-start-pos current-line end-in-day) 'org-timeline-occupied))
		      (put-text-property start-pos end-pos 'font-lock-face 'org-timeline-conflict)  ;; Warning face for conflicts
		    (put-text-property start-pos end-pos 'font-lock-face face))
		  (put-text-property start-pos end-pos 'org-timeline-occupied t)
		  (when name
		    (put-text-property start-pos end-pos 'help-echo name))
		  ))))
	  (buffer-string))))))

(defun org-timeline-insert-timeline ()
  "Insert graphical timeline into agenda buffer."
  (interactive)
  (unless (buffer-narrowed-p)
    (goto-char (point-min))
    (while (and (eq (get-text-property (line-beginning-position) 'org-agenda-type) 'agenda)
                (not (eobp)))
      (forward-line))
    (forward-line)
    (let ((inhibit-read-only t))
      (insert (org-timeline--generate-timeline))
      (insert (propertize (concat "\n" (make-string (/ (window-width) 2) ?─)) 'face 'org-time-grid) "\n"))
    ;; enable `font-lock-mode' in agenda view to display the "chart"
    (font-lock-mode)))

(provide 'org-timeline)
;;; org-timeline.el ends here
