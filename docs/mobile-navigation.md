# Mobile workspace — batch 4 (#108)

Approved phones enter five destinations: Hôm nay, Lịch hẹn, Khách hàng, Hóa đơn, Thêm. Pairing is onboarding; connection controls live in Thêm. The workspace owns its nested navigator. Access loss, backgrounding or a revoked credential removes lists, details, pickers and editors together. Business records are fetched from the desktop; Android does not create a salon database.

Customer search uses the desktop's name/phone query with pagination. Profiles group contact, care information and notes. Lists keep search, selected appointment day and scroll on detail/back and tab changes. Saving refreshes the loaded pages with the same filter. Customer editors require name/phone, validate phone/email beside fields, use appropriate keyboards and preserve optional notes/profile and existing custom tiers.

Appointments are sorted by the desktop in a daily timeline. Date/time dialogs display salon wall-clock time; wire payloads remain canonical day/time. Customer/service/employee selection searches and pages on the server, preserves IDs and service selections between pages, limits services to 20, and rejects catalog epoch changes. Status choices remain the backend's existing values. Actions follow the approved phone role and pending-command lock.

Editors confirm discarding unsaved input on back/reload, retain input on known write rejection, and use the desktop snapshot revision/epoch. Saving uses the unchanged encrypted pending-command controller and commandId protocol; uncertain writes stay durable and block new writes. Checking/retrying uses the original command. Re-enter/reload is required after recovery to obtain the current revision. The existing bill workflow remains available through Hóa đơn / Lập bill; its redesign belongs to #109.

CI widget checks cover navigation/back/search retention, read-only access, desktop IDs/revision, field validation/keyboards, picker dialogs, dirty back/reload, uncertainty and narrow/large-text/keyboard layouts. Linux CI also publishes eight engine-rendered screenshots as the `mobile-ui-review` artifact for visual inspection. These are Flutter engine renders with deterministic fixtures and a readable CI font, not Android device screenshots.

No local app build/test was run. Physical-phone connection, interaction and installation remain unverified and are tracked separately in #111.
