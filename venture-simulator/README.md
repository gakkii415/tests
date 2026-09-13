# Venture Simulator OS

Simulation-first Business OS for testing a new business before committing money, accounts, equipment, or public profiles.

## MVP features

- One Business Spec as the source of truth
- Business-name candidate generation (local simulation generator)
- Simulated email address and domain
- Editable three-tier pricing
- Instant website mock/preview
- Google Business Profile mock
- Equipment, skills, and workflow checklists
- Simple revenue / cost / break-even simulation
- Launch readiness score
- Duplicate / fork / delete simulations
- JSON export/import
- Local browser persistence with `localStorage`
- Responsive UI for iPhone and desktop

## AI integration

This public GitHub Pages build intentionally does **not** contain an API key. The current generation buttons use a local simulation generator. The UI and data model are structured so a secure AI backend can later replace the local generators without changing the product concept.

Never commit an OpenAI API key to this repository or ship it in browser code.

## Run

Open `index.html` directly, or serve the directory with any static HTTP server.

## Data

Data is stored in the current browser's `localStorage`. Use the export button to back up a simulation as JSON.
