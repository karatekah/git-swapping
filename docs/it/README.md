<div align="center">

<img src="../assets/git-swapping-mark.svg" width="96" height="96" alt="Simbolo dei due profili di Git Swapping" />

# Git Swapping

[English](../../README.md) · [Español](../es/README.md) · **Italiano**

**Ogni repository, con il suo account.**

Profili Git per repository da PowerShell.

[![v0.1.0-alpha.3](https://img.shields.io/badge/release-v0.1.0--alpha.3-256b56?style=flat-square)](../releases/v0.1.0-alpha.3.md) [![CI](https://github.com/karatekah/git-swapping/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/karatekah/git-swapping/actions/workflows/ci.yml) [![Windows](https://img.shields.io/badge/piattaforma-Windows-64748b?style=flat-square)](#requisiti)

[Avvio rapido](#avvio-rapido) · [Comandi](#comandi) · [Note alfa.3](../releases/v0.1.0-alpha.3.md) · [Segnala un errore](https://github.com/karatekah/git-swapping/issues)

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

Queste istruzioni usano `main`, che include l'installazione guidata e la gestione interattiva dei profili introdotte in `v0.1.0-alpha.3`.

```powershell
git clone https://github.com/karatekah/git-swapping.git
cd git-swapping
.\install.ps1
git-profile list
```

Il programma di installazione chiede un'etichetta per ciascun profilo, il nome e l'indirizzo email per i commit e il nome utente GitHub. Puoi usare etichette come `personal` o `lavoro`. Il nome utente GitHub deve corrispondere al proprietario del repository. Per i commit puoi usare un indirizzo `noreply` di GitHub.

Il comando è disponibile nella sessione corrente e nelle successive sessioni dello stesso host di PowerShell. Esegui lo script in ogni edizione o host che usi. Se `profiles.psd1` esiste, lo script riutilizza gli account e salva una copia del profilo di PowerShell prima di modificarlo.

In un progetto personale:

```powershell
cd C:\percorso\progetto-personale
git-profile use -Auto -WhatIf
git-profile use -Auto
git-profile status
git fetch origin
```

`-Auto` sceglie il profilo il cui nome utente GitHub corrisponde al proprietario di `origin`. Richiede URL compatibili per fetch e push e `origin` come remoto di push predefinito. Per scegliere manualmente, esegui `git-profile use personal` o usa l'etichetta che hai configurato. Ogni repository conserva la propria configurazione quando cambi cartella.

## Comandi

| Comando | Funzione |
| --- | --- |
| `git-profile` oppure `git-profile help` | Mostrare utilizzo e versione |
| `git-profile list` | Elencare i profili, anche fuori da un repository |
| `git-profile add PROFILO` | Creare un profilo con l'identità per i commit e il nome utente GitHub |
| `git-profile edit PROFILO` | Modificare un profilo salvato. Premi Invio per mantenere il valore di un campo |
| `git-profile remove PROFILO` | Rimuovere un profilo salvato dopo aver confermato |
| `git-profile current` | Mostrare l'identità locale e gli URL effettivi di fetch e push di `origin` |
| `git-profile use PROFILO` | Verificare e applicare il profilo scelto al repository |
| `git-profile use -Auto` | Scegliere e applicare il profilo in base al proprietario di `origin` |
| `git-profile use -Auto -WhatIf` | Vedere il profilo, l'identità e gli URL effettivi prima di salvare. Funziona anche con un profilo esplicito |
| `git-profile check` | Verificare il profilo, il proprietario e gli URL di `origin`, il remoto predefinito per il push e le identità effettive di autore e committer |
| `git-profile status` | Mostrare il profilo atteso, le identità effettive e la provenienza delle impostazioni in conflitto |
| `git-profile audit [CARTELLA]` | Controllare ricorsivamente il profilo atteso e i problemi di configurazione di ogni albero di lavoro Git |

Esegui `list`, `add`, `edit` o `remove` da qualsiasi directory. Questi comandi gestiscono gli account nel file locale `profiles.psd1`. Per applicare un'identità modificata a un repository, esegui `git-profile use PROFILO` al suo interno. Digita `y` per confermare la rimozione o premi Invio per annullarla. Se rimuovi un profilo salvato, i repository conservano l'identità e gli URL già applicati. Se l'elenco è vuoto, puoi creare un nuovo profilo con `add`.

Gli errori generano eccezioni PowerShell, gestibili con `try` / `catch`. La funzione non chiude il terminale. `use` conferma il salvataggio; esegui `check` per rilevare altre impostazioni che sovrascrivono l'identità.

Nella versione di sviluppo, `git-profile audit 'C:\Progetti'` controlla la cartella e le sottocartelle senza connessione e in sola lettura. Se ometti il percorso, parte dalla cartella corrente. Salta le sottocartelle collegate. Il risultato `OK` indica che la configurazione locale ha superato i controlli. Il comando seguente mostra tutti i motivi dei casi da esaminare.

```powershell
git-profile audit 'C:\Progetti' | Where-Object Result -eq 'Review' | Format-List
```

Se `git push` senza argomenti seleziona una destinazione diversa da `origin`, `check` e `status` indicano l'impostazione Git responsabile e la sua provenienza. La verifica avviene senza connessione. `use` richiede che `origin` sia definito direttamente nella configurazione Git locale. In presenza di una regola `includeIf.hasconfig:remote.*.url`, configura `origin` con l'account HTTPS desiderato prima di eseguire `use`.

## Identità e autenticazione

Autore del commit, utente nell'URL e credenziale di autenticazione sono distinti. `check` funziona senza rete e non verifica permessi remoti. Un fetch riuscito dimostra accesso in lettura; non dimostra permessi push e non identifica la credenziale utilizzata.

Lo strumento mantiene credenziali e configurazione globale esistenti e non cambia l'account attivo di `gh`. I commit precedenti conservano i propri metadati; `noreply` protegge i nuovi commit.

## Architettura e sviluppo

| Parte | Implementazione |
| --- | --- |
| CLI | Funzione in `git-profile.ps1`, caricata da `$PROFILE` |
| Installazione | `install.ps1` configura gli account e registra la funzione |
| Account | File dati locale `profiles.psd1` |
| Configurazione | Git installato, codici di uscita verificati e sostituzione atomica |
| Test | Repository temporanei reali, senza rete né credenziali salvate |
| CI | GitHub Actions su Windows PowerShell 5.1 e PowerShell 7 |

I test richiedono Git 2.32 o successivo per isolare la configurazione Git dell'utente. Non serve installare altre dipendenze:

```powershell
powershell -NoProfile -File .\tests\git-profile.Tests.ps1
# Con PowerShell 7 installato:
pwsh -NoProfile -File .\tests\git-profile.Tests.ps1
```

I test coprono entrambi i profili, ripetizione, proprietario errato, URL push separati, lock, scritture fallite e identità che sovrascrivono il profilo.

## Documentazione e prossimi passi

- [Ambito e verifica dell'alfa.3](../releases/v0.1.0-alpha.3.md) · [Changelog](../../CHANGELOG.md).
- Prossimi passi: riscontri su altri PC Windows e associazioni dei proprietari più flessibili. SSH e altri provider richiedono una progettazione specifica dell'autenticazione.

Se sposti o rinomini la copia, esegui `install.ps1` dalla nuova posizione. Salva una copia di `profiles.psd1` prima di eliminare il repository perché Git esclude il file.

---

[Made by Karatekah](https://github.com/karatekah)
