# El Grande — versione digitale

Adattamento digitale non ufficiale, per uso personale, di **El Grande** di Wolfgang Kramer e Richard Ulrich
(Hans im Glück / Rio Grande Games), gioco base. Fatto in Godot 4.7, tutto in italiano.

**Gioca:** https://tannoiser2.github.io/EL-GRANDE/

## Cosa c'è
- **Regole complete del gioco base** dal regolamento italiano: carte potere 1–13, le 45 carte azione delle cinque pile
  (intrighi, Veto!, valutazioni speciali, segna-punti mobili, Consigliere reale, Grande, carta del Re…), il Re e la sua
  regione tabù, il Castillo con i dischi segreti, bonus del Re e della regione di provenienza, parità che scalano di
  una posizione, punteggi ridotti in 2 e 3 giocatori.
- **Partita lunga (9 round) o corta (6 round)**, Castillo **scoperto** o **coperto** (i Caballeros dentro si devono ricordare).
- **Da 2 a 5 giocatori**, umani e **IA** (Facile, Normale, Difficile) in qualunque combinazione, hotseat con la "tenda"
  per le scelte segrete.
- **Gioco online** su Firebase: ognuno dal suo dispositivo con un codice di 4 lettere.
- Tabellone originale ripulito dai riquadri del modulo TTS, carte azione rifatte in italiano con le illustrazioni
  originali, carte potere originali. Titoli in UnifrakturMaguntia, testi in Alegreya (caratteri OFL).

## L'IA
Valuta la posizione come i punti che ogni giocatore farebbe se tutto venisse valutato adesso, rispetto agli
avversari (con più peso a chi è in testa), e simula ogni alternativa: carta azione, ordine fra piazzamento e azione
speciale, dove piazzare, chi spostare con gli intrighi, dove mandare il Re o il Grande. In più:
- le maggioranze contano meno quando la valutazione generale è lontana, perché possono ancora cambiare;
- i Caballeros nel Castillo valgono per quello che renderanno spostandoli nella regione migliore;
- i Caballeros a corte perdono valore verso la fine della partita.
I pesi sono stati tarati con migliaia di partite simulate contro la versione precedente: in 4 giocatori la nuova
vince il 43% delle partite (contro il 25% atteso), in 3 il 44%, in 5 il 31%.
"Facile" e "Normale" aggiungono un po' di casualità alle scelte, "Difficile" no.

## Interpretazioni della versione digitale
- Il regolamento italiano dà Valencia 5/3/2: vale il tabellone (5/3/1).
- Le due carte "Autorità in declino" del modulo TTS hanno la stessa immagine; come da regolamento una fa rimandare
  3 Caballeros della corte, l'altra tutti.
- Il Veto annulla l'intera azione speciale (non il piazzamento). Viene chiesto prima che l'azione cominci.
- Se tutte le carte potere rimaste in mano hanno valori già giocati nel round, se ne gioca una qualsiasi e si va
  dopo chi l'aveva giocata prima.

## Comandi
Clic sulle regioni evidenziate per scegliere o piazzare, tasto destro per togliere. Passando il mouse su una regione
si vedono i Caballeros presenti e i punti che darebbe se fosse valutata adesso. Le carte azione si leggono passandoci
sopra il mouse. F11 schermo intero.

## Gioco online
Dal menu, **Gioca online**. Usa lo stesso progetto Firebase degli altri giochi della ludoteca, con le stanze sotto
`elgrande/rooms`: la sezione generica `$game` di `firebase/database.rules.json` lo copre già.
Chi crea la stanza sceglie nel menu i colori e le opzioni; gli amici entrano con il codice. Ogni decisione è una mossa
numerata (`acts/0`, `acts/1`, …) e tutti i dispositivi giocano la stessa partita con lo stesso seme. Chi cade rientra
con lo stesso codice; chi tace per un minuto viene sostituito dall'IA.

## Struttura
```
scripts/data/eg_data.gd       regioni, confini, valori, carte potere e carte azione
scripts/core/engine.gd        regole e svolgimento della partita
scripts/core/ai.gd            giocatori artificiali
scripts/ui/                   menu, tabellone, carte, vista di gioco, regole
scripts/net/                  Firebase (REST) e partita online in lockstep
tests/                        simulazioni, screenshot, prova online con finto Firebase
```

## Prove
```
godot --headless --path . -s tests/sim.gd -- 10 4 1                     # 10 partite fra IA, 4 giocatori
EG_BASE=1 EG_LVL0=2 godot --headless --path . -s tests/sim.gd -- 60 4 2  # IA attuale contro quella di riferimento (tests/ai_base.gd)
python3 tests/firebase_mock.py 8765 & …tests/online_play.gd             # due dispositivi online sul finto Firebase
xvfb-run godot --path . -s res://tests/shot.gd -- game                  # screenshot
```
La pubblicazione su GitHub Pages è automatica a ogni push su `main` (`.github/workflows/pages.yml`).
