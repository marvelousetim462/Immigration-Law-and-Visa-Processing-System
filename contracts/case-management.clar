;; Immigration Law Case Management Contract
;; Manages the creation, assignment, and tracking of immigration cases

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CASE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-INPUT (err u102))
(define-constant ERR-CASE-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-STATUS (err u104))

;; Data Variables
(define-data-var next-case-id uint u1)
(define-data-var contract-active bool true)

;; Data Maps
(define-map cases
  { case-id: uint }
  {
    client: principal,
    attorney: principal,
    case-type: (string-ascii 50),
    jurisdiction: (string-ascii 20),
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    priority: uint,
    description: (string-ascii 500)
  }
)

(define-map case-permissions
  { case-id: uint, user: principal }
  { can-read: bool, can-write: bool, can-admin: bool }
)

(define-map attorney-cases
  { attorney: principal, case-id: uint }
  { assigned-at: uint, role: (string-ascii 20) }
)

(define-map client-cases
  { client: principal, case-id: uint }
  { created-at: uint }
)

;; Valid case types
(define-map valid-case-types
  { case-type: (string-ascii 50) }
  { active: bool }
)

;; Valid case statuses
(define-map valid-statuses
  { status: (string-ascii 20) }
  { active: bool }
)

;; Initialize valid case types
(map-set valid-case-types { case-type: "H1B-VISA" } { active: true })
(map-set valid-case-types { case-type: "GREEN-CARD" } { active: true })
(map-set valid-case-types { case-type: "CITIZENSHIP" } { active: true })
(map-set valid-case-types { case-type: "FAMILY-VISA" } { active: true })
(map-set valid-case-types { case-type: "STUDENT-VISA" } { active: true })
(map-set valid-case-types { case-type: "ASYLUM" } { active: true })
(map-set valid-case-types { case-type: "DEPORTATION-DEFENSE" } { active: true })

;; Initialize valid statuses
(map-set valid-statuses { status: "INITIAL" } { active: true })
(map-set valid-statuses { status: "DOCUMENTATION" } { active: true })
(map-set valid-statuses { status: "FILED" } { active: true })
(map-set valid-statuses { status: "PENDING" } { active: true })
(map-set valid-statuses { status: "APPROVED" } { active: true })
(map-set valid-statuses { status: "DENIED" } { active: true })
(map-set valid-statuses { status: "APPEAL" } { active: true })
(map-set valid-statuses { status: "CLOSED" } { active: true })

;; Private Functions

(define-private (is-valid-case-type (case-type (string-ascii 50)))
  (default-to false (get active (map-get? valid-case-types { case-type: case-type })))
)

(define-private (is-valid-status (status (string-ascii 20)))
  (default-to false (get active (map-get? valid-statuses { status: status })))
)

;; Fixed permission checking function to avoid type mismatch
(define-private (has-case-permission (case-id uint) (user principal) (permission (string-ascii 10)))
  (let ((perms (map-get? case-permissions { case-id: case-id, user: user })))
    (if (is-some perms)
      (let ((perm-data (unwrap! perms false)))
        (if (is-eq permission "read")
          (get can-read perm-data)
          (if (is-eq permission "write")
            (get can-write perm-data)
            (if (is-eq permission "admin")
              (get can-admin perm-data)
              false))))
      false))
)

(define-private (is-case-participant (case-id uint) (user principal))
  (let ((case-data (map-get? cases { case-id: case-id })))
    (if (is-some case-data)
      (let ((case-info (unwrap! case-data false)))
        (or
          (is-eq user (get client case-info))
          (is-eq user (get attorney case-info))
          (has-case-permission case-id user "read")))
      false))
)

;; Public Functions

;; Create a new immigration case
(define-public (create-case
  (client principal)
  (attorney principal)
  (case-type (string-ascii 50))
  (jurisdiction (string-ascii 20))
  (priority uint)
  (description (string-ascii 500)))
  (let ((case-id (var-get next-case-id)))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-case-type case-type) ERR-INVALID-INPUT)
    (asserts! (< priority u6) ERR-INVALID-INPUT)
    (asserts! (> (len jurisdiction) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)

    ;; Create the case
    (map-set cases
      { case-id: case-id }
      {
        client: client,
        attorney: attorney,
        case-type: case-type,
        jurisdiction: jurisdiction,
        status: "INITIAL",
        created-at: block-height,
        updated-at: block-height,
        priority: priority,
        description: description
      })

    ;; Set permissions
    (map-set case-permissions
      { case-id: case-id, user: client }
      { can-read: true, can-write: false, can-admin: false })

    (map-set case-permissions
      { case-id: case-id, user: attorney }
      { can-read: true, can-write: true, can-admin: true })

    ;; Track attorney-case relationship
    (map-set attorney-cases
      { attorney: attorney, case-id: case-id }
      { assigned-at: block-height, role: "PRIMARY" })

    ;; Track client-case relationship
    (map-set client-cases
      { client: client, case-id: case-id }
      { created-at: block-height })

    ;; Increment case ID counter
    (var-set next-case-id (+ case-id u1))

    (ok case-id))
)

;; Update case status
(define-public (update-case-status (case-id uint) (new-status (string-ascii 20)))
  (let ((case-data (map-get? cases { case-id: case-id })))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-some case-data) ERR-CASE-NOT-FOUND)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    (asserts! (has-case-permission case-id tx-sender "write") ERR-NOT-AUTHORIZED)

    (let ((current-case (unwrap-panic case-data)))
      (map-set cases
        { case-id: case-id }
        (merge current-case { status: new-status, updated-at: block-height }))
      (ok true)))
)

;; Assign additional attorney to case
(define-public (assign-attorney (case-id uint) (attorney principal) (role (string-ascii 20)))
  (let ((case-data (map-get? cases { case-id: case-id })))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-some case-data) ERR-CASE-NOT-FOUND)
    (asserts! (has-case-permission case-id tx-sender "admin") ERR-NOT-AUTHORIZED)

    ;; Set permissions for new attorney
    (map-set case-permissions
      { case-id: case-id, user: attorney }
      { can-read: true, can-write: true, can-admin: false })

    ;; Track attorney-case relationship
    (map-set attorney-cases
      { attorney: attorney, case-id: case-id }
      { assigned-at: block-height, role: role })

    (ok true))
)

;; Grant case permissions to user
(define-public (grant-permissions
  (case-id uint)
  (user principal)
  (can-read bool)
  (can-write bool)
  (can-admin bool))
  (let ((case-data (map-get? cases { case-id: case-id })))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-some case-data) ERR-CASE-NOT-FOUND)
    (asserts! (has-case-permission case-id tx-sender "admin") ERR-NOT-AUTHORIZED)

    (map-set case-permissions
      { case-id: case-id, user: user }
      { can-read: can-read, can-write: can-write, can-admin: can-admin })

    (ok true))
)

;; Update case priority
(define-public (update-case-priority (case-id uint) (new-priority uint))
  (let ((case-data (map-get? cases { case-id: case-id })))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-some case-data) ERR-CASE-NOT-FOUND)
    (asserts! (< new-priority u6) ERR-INVALID-INPUT)
    (asserts! (has-case-permission case-id tx-sender "write") ERR-NOT-AUTHORIZED)

    (let ((current-case (unwrap-panic case-data)))
      (map-set cases
        { case-id: case-id }
        (merge current-case { priority: new-priority, updated-at: block-height }))
      (ok true)))
)

;; Read-only Functions

;; Get case details
(define-read-only (get-case (case-id uint))
  (let ((case-data (map-get? cases { case-id: case-id })))
    (if (and (is-some case-data) (is-case-participant case-id tx-sender))
      (ok case-data)
      ERR-NOT-AUTHORIZED))
)

;; Get case permissions for user
(define-read-only (get-case-permissions (case-id uint) (user principal))
  (if (has-case-permission case-id tx-sender "admin")
    (ok (map-get? case-permissions { case-id: case-id, user: user }))
    ERR-NOT-AUTHORIZED)
)

;; Check if user has specific permission
(define-read-only (check-permission (case-id uint) (user principal) (permission (string-ascii 10)))
  (ok (has-case-permission case-id user permission))
)

;; Get next case ID
(define-read-only (get-next-case-id)
  (ok (var-get next-case-id))
)

;; Check if case type is valid
(define-read-only (is-case-type-valid (case-type (string-ascii 50)))
  (ok (is-valid-case-type case-type))
)

;; Check if status is valid
(define-read-only (is-status-valid (status (string-ascii 20)))
  (ok (is-valid-status status))
)

;; Get attorney assignment info
(define-read-only (get-attorney-assignment (attorney principal) (case-id uint))
  (ok (map-get? attorney-cases { attorney: attorney, case-id: case-id }))
)

;; Admin Functions

;; Add new valid case type (contract owner only)
(define-public (add-case-type (case-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set valid-case-types { case-type: case-type } { active: true })
    (ok true))
)

;; Add new valid status (contract owner only)
(define-public (add-status (status (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set valid-statuses { status: status } { active: true })
    (ok true))
)

;; Toggle contract active state (contract owner only)
(define-public (toggle-contract-active)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok (var-get contract-active)))
)
