<div align="center">

<img src="../assets/githubswapping-mark.svg" width="96" height="96" alt="Simbolo terminale GithubSwapping" />

# GithubSwapping

[English](../../README.md) · [Español](../es/README.md) · **Italiano**

**Ogni repository, con il suo account.**

Una piccola CLI PowerShell per separare le identità Git personali e universitarie, repository per repository.

[![v0.1.0-alpha.2](https://img.shields.io/badge/release-v0.1.0--alpha.2-256b56?style=flat-square)](../releases/v0.1.0-alpha.2.md) [![CI](https://github.com/karatekah/GithubSwapping/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/karatekah/GithubSwapping/actions/workflows/ci.yml) [![Windows](https://img.shields.io/badge/piattaforma-Windows-64748b?style=flat-square)](#requisiti)

[Avvio rapido](#avvio-rapido) · [Comandi](#comandi) · [Note alfa](../releases/v0.1.0-alpha.2.md) · [Segnala un errore](https://github.com/karatekah/GithubSwapping/issues)

</div>

---

Assegna un profilo una volta e lavora in ogni progetto con la sua identità locale. **Alfa sperimentale:** un account GitHub per proprietario, remoti HTTPS e controlli espliciti.

## Funzioni dell'alfa

- Identità locale con `user.name` e `user.email`, mantenendo la configurazione globale.
- Verifica del proprietario prima di applicare un profilo: progetti personali e universitari restano separati.
- Controllo degli URL di fetch e push, aggiornando anche un `pushurl` esplicito. Devono indicare lo stesso repository.
- Modifiche preparate sotto lock e sostituzione atomica della configurazione, evitando aggiornamenti parziali.
- Errori espliciti per comandi Git falliti, remoti mancanti, URL incompatibili e identità in conflitto.
- Dati reali in `profiles.psd1`, escluso da Git; nel repository è inclusa soltanto una configurazione di esempio.

## Requisiti

Windows PowerShell 5.1 o PowerShell 7 su Windows; Git 2.31 o successivo in `PATH`; autenticazione HTTPS già configurata, per esempio con Git Credential Manager.

Sono supportati repository di lavoro normali con un URL fetch di `origin` e al massimo un URL push esplicito. SSH, repository bare, GitHub Enterprise, URL multipli e file di configurazione simbolici non sono supportati. La sostituzione atomica richiede un filesystem locale compatibile.

## Avvio rapido

In una nuova copia:

```powershell
git clone https://github.com/karatekah/GithubSwapping.git
cd GithubSwapping
Copy-Item .\profiles.example.psd1 .\profiles.psd1
notepad .\profiles.psd1
```

Inserisci nomi, email e nomi utente GitHub. `personal` e `unsa` sono etichette; il campo `GitHub` deve corrispondere al proprietario del repository. Puoi usare l'indirizzo `noreply` fornito da GitHub per proteggere l'email personale nei nuovi commit.

```powershell
. .\git-profile.ps1
git-profile list
```

Aggiungi **una sola volta** questo caricamento al tuo `$PROFILE`, sostituendo il percorso con quello assoluto della copia:

```powershell
if (Test-Path -LiteralPath 'C:\percorso\GithubSwapping\git-profile.ps1') {
    . 'C:\percorso\GithubSwapping\git-profile.ps1'
}
```

Crea prima il file del profilo e la cartella, se mancano. Conserva il resto del contenuto. Windows PowerShell e PowerShell 7 usano profili distinti. Riavvia il terminale oppure esegui `. $PROFILE` dopo la modifica.

In un progetto personale:

```powershell
cd C:\percorso\progetto-personale
git-profile use personal
git-profile status
git fetch origin
```

Per un progetto dell'account universitario usa `git-profile use unsa`. Ogni repository conserva la propria configurazione quando cambi cartella.

## Comandi

| Comando | Funzione |
| --- | --- |
| `git-profile` oppure `git-profile help` | Mostrare utilizzo e versione |
| `git-profile list` | Elencare i profili, anche fuori da un repository |
| `git-profile current` | Mostrare identità locale e URL effettivi di fetch e push |
| `git-profile use PROFILO` | Verificare il proprietario e applicare identità e URL locali |
| `git-profile check` | Verificare profilo, proprietario, URL e identità effettive di autore e committer |
| `git-profile status` | Mostrare lo stato ed eseguire la stessa verifica |

Gli errori generano eccezioni PowerShell, gestibili con `try` / `catch`. La funzione non chiude il terminale. `use` conferma il salvataggio; esegui `check` per rilevare altre impostazioni che sovrascrivono l'identità.

## Identità e autenticazione

Autore del commit, utente nell'URL e credenziale di autenticazione sono distinti. `check` funziona senza rete e non verifica permessi remoti. Un fetch riuscito dimostra accesso in lettura; non dimostra permessi push e non identifica la credenziale utilizzata.

Lo strumento mantiene credenziali e configurazione globale esistenti e non cambia l'account attivo di `gh`. I commit precedenti conservano i propri metadati; `noreply` protegge i nuovi commit.

## Architettura e sviluppo

| Parte | Implementazione |
| --- | --- |
| CLI | Funzione in `git-profile.ps1`, caricata da `$PROFILE` |
| Account | File dati locale `profiles.psd1` |
| Configurazione | Git installato, codici di uscita verificati e sostituzione atomica |
| Test | Repository temporanei reali, senza rete né credenziali salvate |
| CI | GitHub Actions su Windows PowerShell 5.1 e PowerShell 7 |

Non serve installare dipendenze:

```powershell
powershell -NoProfile -File .\tests\git-profile.Tests.ps1
# Con PowerShell 7 installato:
pwsh -NoProfile -File .\tests\git-profile.Tests.ps1
```

I test coprono entrambi i profili, ripetizione, proprietario errato, URL push separati, lock, scritture fallite e identità che sovrascrivono il profilo.

## Documentazione e prossimi passi

- [Ambito e verifica dell'alfa](../releases/v0.1.0-alpha.2.md) · [Changelog](../../CHANGELOG.md).
- Prossimi passi: riscontri su altri PC Windows, un supporto all'installazione e associazioni dei proprietari più flessibili. SSH e altri provider richiedono una progettazione specifica dell'autenticazione.

Se sposti la copia, aggiorna il percorso in `$PROFILE`. Salva una copia di `profiles.psd1` prima di eliminarla: Git non archivia i tuoi account.

---

[Made by Karatekah](https://github.com/karatekah)
