# ShootMap — Project Overview

> Reference document. Guidance only — no implementation is derived from this file automatically.

## What it is

ShootMap is an iOS app that connects **photographers** and **viewers** through a map.
Photographers publish a planned photography session by pinning a location and specifying the date and time.
Viewers browse those sessions on a map and see the photographer's details.

---

## User journeys

### Photographer

1. Sign up as a **Photographer**.
2. Add their Facebook Page name / link.
3. Pin a photography location on the map.
4. Select the **date**, **start time**, and **end time**.
5. Publish the session.
6. The session is saved to **Firebase Firestore** and cached locally with **SwiftData**.

### Viewer

1. Sign up as a **Viewer**.
2. Open the map.
3. See available / upcoming photography sessions.
4. Tap a pin to view:
   - Photographer
   - Facebook Page
   - Location
   - Date
   - Time
5. Optionally open the photographer's Facebook Page.

---

## 📸 Screenshots / Demo

| Login Page | Create Photographer Account | Create Viewer Account |
| --- | --- | --- |
|<img width="350" height="650" alt="Login page" src="https://github.com/user-attachments/assets/8b1166dd-7869-48c2-b667-e3b466bfc6d6" />| <img width="350" height="650" alt="Create Photographer Account" src="https://github.com/user-attachments/assets/133bbd10-b62a-4c42-9cbc-31d0cae6c2fd" /> | <img width="350" height="650" alt="Create Viewer Account" src="https://github.com/user-attachments/assets/6025fa00-3c07-45dc-9561-024aa1d965a3" /> |

## Photographer Page
| Landing/Session Page | My Sessions | Session Details | Create Session Part1 | Create Session Final |
| --- | --- | --- | --- | --- |
|<img width="350" height="650" alt="Photographer Landing:Session Page" src="https://github.com/user-attachments/assets/b175cb65-4725-4e3c-a71a-50ace5c79892" /> | <img width="350" height="650" alt="Photographer My Session" src="https://github.com/user-attachments/assets/ae1b3fcf-7cad-4ec0-a88b-c4167ab8a22f" /> | <img width="350" height="650" alt="Photographer Session Details Page" src="https://github.com/user-attachments/assets/743312be-29df-4645-aea3-399bc8bfd6c9" /> | <img width="350" height="650" alt="Create Session part1" src="https://github.com/user-attachments/assets/7faa0dbc-48a7-4413-9456-acadfcdf9e8b" /> | <img width="350" height="650" alt="Create Session Part 2 Final" src="https://github.com/user-attachments/assets/94034bc5-b663-4234-9e8b-dfff1ec99410" /> |

## Viewer Page
| Landing Page | Session Details |
| --- | --- |
| <img width="350" height="650" alt="Viewer Landing Page" src="https://github.com/user-attachments/assets/0ec35f36-9d1a-444c-88e2-11966c7607d1" /> | <img width="350" height="650" alt="Viewer Session Details Page" src="https://github.com/user-attachments/assets/d22501e3-b55f-4491-8580-27726fdd01ec" /> |

## Architecture

| Concern | Approach |
|---|---|
| Presentation | MVVM-Coordinator — Views are dumb, ViewModels hold state, Coordinators own navigation |
| Abstraction | Protocol-Oriented Programming — every dependency behind a protocol |
| Data access | Repository Pattern — single entry point per aggregate |
| Wiring | Dependency Injection — constructor injection via a DI container/assembler |
| Remote source of truth | Firebase Firestore |
| Local cache | SwiftData |
| Concurrency | Swift concurrency, `async`/`await`, `AsyncStream` for Firestore listeners |

### Layering rules

- **Domain** (`Models/Domain`) — pure value types. No Firebase, no SwiftData, no SwiftUI, no CoreLocation.
- **Data** — DTOs (Firestore), `@Model` entities (SwiftData), mappers, repositories.
- **Presentation** — ViewModels + SwiftUI views + coordinators.
- Dependencies point **inward**: Presentation → Domain ← Data.

### Cache strategy

- Firestore is authoritative; SwiftData mirrors it for offline/instant reads.
- Reads: local-first, then reconcile with remote (read-through).
- Writes: write to Firestore, then update the local mirror.

---

## Domain model (already defined)

Located in `ShootMap/Models/Domain/`:

- `User` — `id`, `email`, `displayName`, `facebookPageName`, `facebookPageURL`, `role`, `createdAt`
- `PhotoSession` — `id`, `photographerId`, `photographerName`, `facebookPageName`, `facebookPageURL`, `latitude`, `longitude`, `date`, `startTime`, `endTime`, `createdAt`, `status`
- `UserRole` — `photographer`, `client`, `admin`
- `SessionStatus` — `scheduled`, `ongoing`, `completed`, `cancelled`
- Supporting: `Coordinate`, `DomainValidationError`, `DomainProtocols`, `String+Domain`

### Invariants enforced in the domain

- Latitude in `-90...90`, longitude in `-180...180`.
- `endTime` must be strictly after `startTime`.
- Session duration between 5 minutes and 24 hours.
- `startTime` must fall on the same calendar day as `date`.
- Photographers must have a Facebook page name or URL.
- Session status changes follow a state machine (`scheduled → ongoing → completed`, cancel from either active state).

---

## Open items / decisions to confirm

1. **Terminology**: the overview calls the second role a **"Viewer"**, while `UserRole` currently uses `client`.
   Pick one — renaming the case to `viewer` is the cleaner fit for this product.
2. Discovery radius / map query strategy (Firestore geo-queries vs. client-side filtering of a bounded set).
3. Whether viewers can contact/book a photographer, or the Facebook Page is the only call-to-action.
4. Retention: when are `completed`/`cancelled` sessions dropped from the local cache?
5. Auth provider(s): email/password only, or Sign in with Apple / Facebook Login as well.

---

## Concurrency note

The target uses Swift 6.2 **default main-actor isolation**. Domain types are explicitly marked
`nonisolated` so they remain `Sendable` and actor-agnostic. Keep this convention for all new
domain, repository, and DTO types; reserve `@MainActor` for ViewModels, coordinators, and views.

---

## License

Copyright © 2026 Septuagint Murito. All rights reserved. See [LICENSE](LICENSE).

This repository is publicly available for portfolio, educational and demonstration purposes only. Copying, modifying, distributing, sublicensing or using this source code (or substantial portions of it) for commercial purposes requires prior written permission from the copyright holder. Viewing and forking through GitHub is permitted in accordance with GitHub's Terms of Service.
