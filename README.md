# Calendario Tango

Calendario mobile degli eventi pubblicati su [faitango.it/agenda-eventi](https://www.faitango.it/agenda-eventi).
Ogni mattina GitHub Actions scarica gli eventi dei 60 giorni successivi e ripubblica il sito su GitHub Pages.

- `docs/index.html`: la pagina
- `docs/events.json`: i dati (aggiornati in automatico)
- `scrape-faitango.ps1`: lo script che legge faitango.it
- `.github/workflows/aggiorna.yml`: l'aggiornamento giornaliero

## Messa online (una volta sola)

1. Su github.com crea un nuovo repository **pubblico** (es. `calendario-tango`), senza README.
2. Nella pagina del repository vuoto scegli **uploading an existing file** e trascina **tutto il contenuto**
   della cartella estratta (le cartelle `docs`, `.github` e i file), poi **Commit changes**.
   Se la cartella `.github` non viene caricata, vedi la nota sotto.
3. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
4. **Actions** → workflow **Aggiorna calendario** → **Run workflow**. Dopo circa 2 minuti il sito è online su
   `https://<tuo-utente>.github.io/calendario-tango/`.

Nota: se il caricamento ignora `.github`, crea il file a mano con **Add file → Create new file**,
nome `.github/workflows/aggiorna.yml`, e incolla il contenuto del file `aggiorna.yml`.

## Funzionamento

- L'aggiornamento parte ogni giorno alle 05:00 UTC (06:00 in inverno, 07:00 in estate) e si può lanciare a mano da **Actions → Run workflow**.
- Se faitango.it non risponde o i dati sono incompleti, il workflow fallisce senza toccare i dati già pubblicati; GitHub manda una mail di avviso.
- Sul telefono: apri il link e scegli **Aggiungi a schermata Home** per averlo come un'app.
