# Vocabulary content review — first pass (15 Oct 2026)

First-pass review of the terms flagged in `docs/HANDOFF_COWORK.md` step 6. These are
proposals for a native speaker to confirm, not final. Format: `id → field → new text`.
Fields use the JSON paths in `Packages/VocabCore/Sources/VocabCore/Resources/vocabulary.json`.

Collisions checked: `ödev` is already the TR term for *homework* (school-0008) and `ders` is used for
*lesson* (school-0009) and *subject* (school-0021); `özet` is *summary* (school-0056). Proposals below
avoid creating duplicate TR terms.

## Turkish

| id | field | current | proposed | why |
|---|---|---|---|---|
| dailyLife-0041 | terms.tr | ayak işi | **ayak işi** (keep) | Correct dictionary equivalent, but note it can sound slightly demeaning ("menial chore"). Alternative if a native speaker objects: `ufak iş` + example `Bu sabah halletmem gereken birkaç ufak iş var.` |
| dailyLife-0090 | terms.tr | kayınlar | **eşin ailesi** | `kayınlar` is understood but unidiomatic as a standalone noun. |
| dailyLife-0090 | examples.tr | Noeli kayınlarımla geçiriyoruz. | **Noeli eşimin ailesiyle geçiriyoruz.** | |
| dailyLife-0090 | definitions.tr | Eşinin anne babası ve akrabaları. | (keep) | |
| health-0091 | terms.tr | esenlik | **iyilik hali** | `esenlik` is literary/rare; `iyilik hali` is the term used in health and HR contexts. |
| health-0091 | examples.tr | Yoga fiziksel ve zihinsel esenliği artırır. | **Yoga fiziksel ve zihinsel iyilik halini artırır.** | |
| school-0095 | terms.tr | özet bildiri | **makale özeti** | `bildiri` means *paper/announcement*, so `özet bildiri` reads as "summary paper". `özet` alone collides with school-0056. |
| school-0095 | examples.tr | Tüm makaleden önce özet bildiriyi okuyun. | **Tüm makaleden önce makale özetini okuyun.** | |
| school-0042 | terms.tr | ders anlatımı | **üniversite dersi** | `ders anlatımı` is the *act* of lecturing, not the lecture. `ders` alone collides with lesson/subject. |
| school-0042 | examples.tr | Ders anlatımı iki saat sürdü. | **Üniversite dersi iki saat sürdü.** | |
| school-0043 | terms.tr | görev ödevi | **verilen ödev** | `görev ödevi` is not a phrase. `ödev` alone collides with homework (school-0008). |
| school-0043 | examples.tr | Ödevin teslim tarihi gelecek pazartesi. | (keep) | |
| health-0096 | terms.tr | hastalığın gerilemesi | **remisyon** | Medical term in TR is `remisyon`; the current phrase is a gloss, not a word. |
| health-0096 | examples.tr | Kanserinde beş yıldır gerileme var. | **Kanseri beş yıldır remisyonda.** | |
| school-0039 | terms.tr | akademik derece | **üniversite diploması** | `akademik derece` is formal/rare; everyday Turkish says `diploma` / `lisans`. `diploma` alone collides with school-0045. |
| school-0039 | examples.tr | Mühendislikte lisans derecesi var. | **Mühendislik diploması var.** | |

## Spanish (Spain)

| id | field | current | proposed | why |
|---|---|---|---|---|
| school-0091 | terms.es | asignatura optativa | (keep) | Correct and standard in Spain. |
| dailyLife-0088 | terms.es | charla trivial | **charla de cortesía** | `charla trivial` is a literal gloss; `charla de cortesía` / `conversación de cortesía` is what speakers say. |
| dailyLife-0088 | examples.es | No se me da bien la charla trivial. | **No se me da bien la charla de cortesía.** | |
| travel-0090 | terms.es | ascenso de categoría | **mejora de categoría** | `ascenso` is a job promotion; airlines and hotels in Spain say `mejora de categoría` (or just `upgrade`). |
| travel-0090 | examples.es | Nos dieron un ascenso de categoría gratis a business. | **Nos dieron una mejora de categoría gratis a business.** | |
| technology-0091 | terms.es | suplantación de identidad | **phishing** | `suplantación de identidad` is identity theft/impersonation in general; the specific scam is called `phishing` in Spanish media and by INCIBE. |
| technology-0091 | examples.es | Ese correo que pide tu contraseña es suplantación de identidad. | **Ese correo que pide tu contraseña es phishing.** | |
| technology-0091 | definitions.es | Engaño con mensajes falsos para robar datos personales. | (keep) | |

## French

| id | field | current | proposed | why |
|---|---|---|---|---|
| school-0097 | terms.fr | maître de conférences | **enseignant d'université** | `maître de conférences` is a specific civil-service rank, not the generic "lecturer". |
| school-0097 | examples.fr | Mon maître de conférences m'a conseillé ce livre. | **Mon enseignant d'université m'a conseillé ce livre.** | |
| travel-0074 | terms.fr | en surréservation | **surbooké** | `en surréservation` is correct but only seen in formal notices; everyday French (incl. airline staff) says `surbooké`. |
| travel-0074 | examples.fr | Le vol était en surréservation, j'ai pris le suivant. | **Le vol était surbooké, j'ai pris le suivant.** | |
| business-0051 | terms.fr | succursale | (keep) | Generic word for a branch of a company is `succursale`; a *bank* branch is an `agence`, so the example should not use a bank. |
| business-0051 | examples.fr | La banque a ouvert une succursale au centre-ville. | **La chaîne a ouvert une nouvelle succursale au centre-ville.** | Avoids the bank/agence mismatch while keeping the term. |

## Level placement

| id | field | current | proposed |
|---|---|---|---|
| food-0099 (calorie) | difficulty | advanced | **intermediate** |
| food-0098 (crispy) | difficulty | advanced | **intermediate** |
| food-0100 (expiration date) | difficulty | advanced | **intermediate** |

## English spelling convention

Terms use US spelling, so the recommendation is **US spelling everywhere**. 16 British spellings found in
English definitions/examples:

| id | field | change |
|---|---|---|
| business-0071 | definitions.en | fulfil → **fulfill** |
| dailyLife-0085 | definitions.en | behaviour → **behavior** |
| travel-0077 | definitions.en | behaviour → **behavior** |
| food-0017 | definitions.en | flavour → **flavor** |
| food-0043 | definitions.en | flavour → **flavor** |
| food-0057 | definitions.en | flavour → **flavor** |
| food-0070 | definitions.en | flavour → **flavor** |
| food-0081 | definitions.en | flavour → **flavor** |
| food-0090 | examples.en | fibre → **fiber** |
| health-0070 | definitions.en | defence → **defense** |
| health-0100 | definitions.en | tumour → **tumor** |
| health-0100 | examples.en | tumour → **tumor** |
| school-0098 | definitions.en | analyse → **analyze** |
| technology-0057 | examples.en | cancelled → **canceled** |
| travel-0005 | definitions.en | travelling → **traveling** |
| travel-0069 | definitions.en | travelling → **traveling** |

One-liner to apply the spelling changes once confirmed (run from the repo root):

```
python3 - <<'EOF'
import json,re
p="Packages/VocabCore/Sources/VocabCore/Resources/vocabulary.json"
items=json.load(open(p))
sub={"fulfil":"fulfill","behaviour":"behavior","flavour":"flavor","fibre":"fiber","defence":"defense","tumour":"tumor","analyse":"analyze","cancelled":"canceled","travelling":"traveling"}
for it in items:
    for f in ("definitions","examples"):
        for b,a in sub.items(): it[f]["en"]=re.sub(r"\b"+b+r"\b",a,it[f]["en"])
open(p,"w").write("[\n"+",\n".join("  "+json.dumps(it,ensure_ascii=False) for it in items)+"\n]\n")
EOF
```

(The file is one entry per line; the writer above keeps that format so the diff stays small.)
