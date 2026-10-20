# Notatki w Emacsie: instalacja i pierwsze kroki (Fedora)

**Wersja testowa, październik 2026.** Ta instrukcja jest pierwsza i na pewno czegoś w niej brakuje. Jeśli coś wygląda inaczej niż tu opisano, coś nie działa albo czegoś nie rozumiesz, to właśnie jest najcenniejsza informacja: zapisz ją i przekaż (patrz [Coś nie działa?](#coś-nie-działa)). Nie musisz niczego naprawiać sama ani sam.

Instrukcja jest dla Fedory 43 lub nowszej. Zajmie około pół godziny, w tym kilka minut czekania. Potrzebny jest internet.

## Spis treści

1. [Co to jest i czego się spodziewać](#1-co-to-jest-i-czego-się-spodziewać)
2. [Otwórz terminal](#2-otwórz-terminal)
3. [Zainstaluj programy](#3-zainstaluj-programy)
4. [Pobierz konfigurację](#4-pobierz-konfigurację)
5. [Pierwsze uruchomienie](#5-pierwsze-uruchomienie)
6. [Jak czytać skróty klawiszowe](#6-jak-czytać-skróty-klawiszowe)
7. [Codzienna praca](#7-codzienna-praca)
8. [Gdzie są notatki](#8-gdzie-są-notatki)
9. [Dodatki: włączanie i wyłączanie](#9-dodatki-włączanie-i-wyłączanie)
10. [Aktualizacja](#10-aktualizacja)
11. [Coś nie działa?](#coś-nie-działa)
12. [Znane ograniczenia](#12-znane-ograniczenia)

## 1. Co to jest i czego się spodziewać

Emacs to edytor tekstu, a ta konfiguracja zamienia go w program do notatek: dziennik, notatki, wyszukiwanie, linki między notatkami, sprawdzanie pisowni po polsku i angielsku. Notatki to zwykłe pliki tekstowe w folderze `~/notes`. Żadnej chmury, żadnego konta.

Emacs wygląda inaczej niż typowe programy. Większość rzeczy robi się klawiaturą, a menu z poleceniami otwiera się jednym skrótem (`Ctrl+c`, potem `n`). Na początku wystarczy kilka skrótów z rozdziału 7.

## 2. Otwórz terminal

Terminal to okno, w którym wpisuje się polecenia.

1. Naciśnij klawisz z logo Windows (w Fedorze nazywa się „Super”).
2. Wpisz `terminal` i naciśnij Enter.

Otworzy się okno z migającym kursorem. Polecenia z tej instrukcji kopiujesz (zaznacz myszką, prawy przycisk, „Kopiuj”) i wklejasz do terminala (prawy przycisk, „Wklej” albo `Ctrl+Shift+v`), a potem naciskasz Enter.

## 3. Zainstaluj programy

Wklej do terminala to polecenie i naciśnij Enter:

```sh
sudo dnf install -y emacs git hunspell hunspell-pl hunspell-en-GB ripgrep glibc-langpack-pl adobe-source-sans-pro-fonts
```

- `sudo` oznacza „zrób to jako administrator”. Terminal zapyta o **Twoje hasło** (to samo, którym logujesz się do komputera). Podczas wpisywania hasła **nic się nie pojawia**, nawet kropki. To normalne: wpisz je i naciśnij Enter.
- Instalacja potrwa od kilkudziesięciu sekund do kilku minut. Skończy się, gdy terminal przestanie wypisywać tekst i znów pokaże migający kursor.

Co instalujesz:

| Program | Do czego |
|---|---|
| `emacs` | sam edytor |
| `git` | pobranie konfiguracji i jej aktualizacje |
| `hunspell`, `hunspell-pl`, `hunspell-en-GB` | sprawdzanie pisowni po polsku i angielsku |
| `ripgrep` | szybkie wyszukiwanie w treści notatek |
| `glibc-langpack-pl` | polskie ustawienia daty i języka dla programów |
| `adobe-source-sans-pro-fonts` | czcionka, którą ta konfiguracja pisze notatki |

Programy potrzebne tylko do niektórych rzeczy (możesz je doinstalować później, nic się bez nich nie psuje):

| Do czego | Polecenie |
|---|---|
| oglądanie plików PDF w Emacsie | `sudo dnf install -y autoconf automake gcc libpng-devel make poppler-devel poppler-glib-devel zlib-devel` |
| zmniejszanie wklejanych obrazków | `sudo dnf install -y ImageMagick` |
| eksport do Worda (DOCX) | `sudo dnf install -y libreoffice-writer` |

## 4. Pobierz konfigurację

Emacs szuka swojej konfiguracji w ukrytym folderze `~/.emacs.d` w Twoim katalogu domowym.

**Najpierw sprawdź, czy już go nie masz** (gdybyś kiedyś używała lub używał Emacsa):

```sh
ls -d ~/.emacs.d
```

- Jeśli terminal odpowie `No such file or directory` (albo „Nie ma takiego pliku ani katalogu”), wszystko w porządku, przejdź dalej.
- Jeśli wypisze `/home/…/.emacs.d`, przenieś stary folder w bezpieczne miejsce: `mv ~/.emacs.d ~/.emacs.d.stary`

Teraz pobierz konfigurację:

```sh
git clone https://github.com/waltharius/emacs.git ~/.emacs.d
```

Po chwili zobaczysz kilka linii kończących się czymś w rodzaju `done.`. To wszystko.

## 5. Pierwsze uruchomienie

Uruchom Emacsa z terminala (za pierwszym razem tak będzie lepiej, bo w terminalu widać ewentualne błędy):

```sh
emacs
```

Co się będzie działo:

1. **Kilka minut pobierania.** Emacs pobiera z internetu kilkadziesiąt dodatków. Okno może przez ten czas wyglądać na zawieszone albo migać. Poczekaj, aż się uspokoi. Tylko pierwsze uruchomienie tak trwa.
2. **Okienka z napisem DONE i przyciskiem OK.** To raporty, co Emacs zrobił przy pierwszym starcie. Przeczytaj i kliknij OK. Jeden z nich powie, że ten komputer zaczyna z ustawieniami domyślnymi, i wymieni dodatki wyłączone na start (Readwise, Zotero, import z Obsidiana, blogi, statystyki pisania). Tak ma być, patrz rozdział 9.
3. Gdyby pojawiło się okienko z napisem **FAILED** albo czerwony tekst: zrób zdjęcie ekranu (`PrintScreen`) i przekaż je (rozdział 11). Zwykle Emacs i tak działa dalej.
4. Na końcu otworzy się **pulpit notatek** (Notes Dashboard). Notatek jeszcze nie ma, więc będzie pusty.

Folder `~/notes` z podfolderami tworzy się sam.

Później możesz uruchamiać Emacsa normalnie z menu programów (klawisz Super, wpisz `emacs`).

## 6. Jak czytać skróty klawiszowe

W Emacsie skróty zapisuje się tak:

| Zapis | Znaczy |
|---|---|
| `C-s` | przytrzymaj **Ctrl** i naciśnij **s** |
| `M-x` | przytrzymaj **Alt** i naciśnij **x** |
| `C-c n` | Ctrl+c, puść oba klawisze, potem samo **n** |
| `C-x C-c` | Ctrl+x, potem Ctrl+c |

Dwa skróty warto znać od pierwszej minuty:

- **`C-g`** (Ctrl+g): **anuluj**. Działa zawsze, gdy Emacs o coś pyta, a Ty nie wiesz, co odpowiedzieć, albo coś poszło nie tak. Można nacisnąć kilka razy.
- **`C-c n`**: **menu notatek**. Pokazuje litery i polecenia. Naciśnij literę, żeby wybrać, albo `q`, żeby zamknąć.

Jeśli zaczniesz skrót i poczekasz chwilę, na dole okna pojawi się podpowiedź, jakie klawisze mogą być dalej.

## 7. Codzienna praca

| Co chcesz zrobić | Skrót |
|---|---|
| wpis w dzienniku na dziś | `C-c n` `c` `j` |
| nowa notatka | `C-c n` `c` `n` |
| otwórz notatkę po nazwie | `C-c n` `f` `f` |
| szukaj w treści wszystkich notatek | `C-c n` `f` `g` |
| zapisz | `C-s` |
| cofnij | `C-z` |
| szukaj w otwartej notatce | `C-f` |
| popraw słowo podkreślone na czerwono | kursor na słowie, `C-;` |
| dodaj do słownika ostatnie podkreślone słowo przed kursorem | `C-c S` |
| zamknij Emacsa | `C-x C-c` |

**Dziennik** (`C-c n c j`): pierwszy raz danego dnia tworzy notatkę z dzisiejszą datą, każdy następny raz dopisuje do niej nowy wpis z godziną.

**Nowa notatka** (`C-c n c n`) zada trzy pytania na dole okna:

1. **Title:** tytuł notatki. Wpisz i Enter.
2. **Keywords:** słowa kluczowe, czyli tagi. Możesz wpisać kilka, oddzielając przecinkami, albo nic i Enter.
3. **Save in:** gdzie zapisać. Do wyboru są trzy części notatek (tzw. silosy):
   - `journal`: dziennik,
   - `pks`: wiedza, przemyślenia, notatki do nauki,
   - `docu`: notatki techniczne, instrukcje.

   Wybierz strzałkami i Enter. Jeśli nie wiesz, wybierz `pks`.

Notatki zapisują się w formacie Org: to zwykły tekst, w którym linia zaczynająca się od `*` jest nagłówkiem, `**` podnagłówkiem i tak dalej.

**Uwaga, jeśli znasz Emacsa:** w tej konfiguracji `C-s` zapisuje, `C-f` szuka, a `C-z` cofa, jak w innych programach. W standardowym Emacsie i w jego wbudowanym samouczku te skróty robią co innego.

## 8. Gdzie są notatki

W folderze `~/notes`, czyli `notes` w Twoim katalogu domowym. Każda notatka to jeden plik z końcówką `.org`. Możesz je otworzyć dowolnym edytorem tekstu i skopiować gdziekolwiek.

**Kopia zapasowa:** na razie ta konfiguracja sama nie robi kopii notatek na inny dysk ani do internetu. Kopiuj folder `~/notes` tak, jak inne ważne pliki (np. na pendrive albo do chmury, której używasz).

## 9. Dodatki: włączanie i wyłączanie

Część dodatków jest na start wyłączona, bo potrzebują konta albo innego programu:

| Dodatek | Do czego |
|---|---|
| Readwise | pobieranie zakreśleń z książek i artykułów (konto w readwise.io) |
| Zotero | bibliografia i cytaty z programu Zotero |
| import z Obsidiana | przenoszenie notatek z programu Obsidian |
| blog | publikowanie wybranych notatek jako strony internetowej |
| dokumentacja repozytorium | strona z opisem tej konfiguracji (dla jej autora) |
| statystyki pisania | liczenie, jakich poleceń używasz najczęściej |

Żeby któryś włączyć (albo wyłączyć inny): `C-c n` `,` `m`, wybierz dodatek z listy i Enter. Emacs zapyta, czy włączyć od razu, czy przy następnym uruchomieniu.

## 10. Aktualizacja

Konfiguracja jest rozwijana, poprawki pojawiają się często. Żeby je pobrać, zamknij Emacsa i wpisz w terminalu:

```sh
git -C ~/.emacs.d pull
```

Potem uruchom Emacsa ponownie. Jeśli po aktualizacji coś przestanie działać, napisz o tym (rozdział 11).

## Coś nie działa?

Każda uwaga się przyda: błąd, niejasny komunikat, coś niewygodnego, coś, czego brakuje. Najlepiej przekaż:

1. **Co robiłaś lub robiłeś** (jakie klawisze, w jakiej kolejności).
2. **Co się stało**, a czego się spodziewałaś lub spodziewałeś.
3. **Zdjęcie ekranu** (`PrintScreen`, zapisuje się w folderze Obrazy).
4. **Dziennik komunikatów Emacsa:** w Emacsie `C-h e` otwiera bufor *Messages*. Zaznacz wszystko (`C-x h`), skopiuj (`M-w`) i wklej do wiadomości.
5. **Wersje:** w terminalu `emacs --version` (pierwsza linia) i `cat /etc/fedora-release`.

Zgłoszenia: bezpośrednio do autora konfiguracji, albo na GitHubie w zakładce [Issues](https://github.com/waltharius/emacs/issues) (potrzebne konto na GitHubie).

## 12. Znane ograniczenia

- **Język interfejsu jest mieszany:** menu i komunikaty są po angielsku, szablony notatek po polsku. Polskie menu jest w planach.
- **Czcionka JetBrains Mono** (używana do kodu i tabel) nie jest dostępna w repozytoriach Fedory. Emacs użyje wtedy innej czcionki o stałej szerokości znaków. Jeśli coś wygląda źle, napisz.
- **Foldery są stałe:** notatki w `~/notes`, z podfolderami `journal`, `pks` i `docu`. Zmiana jest możliwa w ustawieniach (`C-c n` `,` `,`), ale na razie nie jest opisana dla początkujących.
- **Samouczka jeszcze nie ma.** Ta instrukcja pokazuje tylko podstawy. Pełny samouczek z ćwiczeniami jest w planach.
