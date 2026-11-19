/// Programs offered by the REPL sample; a test runs each one in Monty.
const replExamples = <Map<String, String>>[
  {
    'label': 'Widget catalog',
    'source': '''
import ui

OWL = "https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg"
BEE = "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4"

def section(title, body):
    return ui.Card(ui.Column([ui.Text(title, "caption"), body]))

def build(note):
    display = ui.Column([
        section("Text", ui.Text("Every widget here was built by Python running in Monty.")),
        section("Icon", ui.Row([ui.Icon(n) for n in
            ["home", "favorite", "star", "mail", "check", "info", "lock", "folder"]],
            "spaceAround")),
        ui.Divider(),
        section("Divider (vertical) in a Row", ui.Row([
            ui.Text("left"), ui.Divider("vertical"), ui.Text("right")])),
    ])
    inputs = ui.Column([
        ui.TextField("Name", ui.bind("/form/name"), "Type a name"),
        ui.CheckBox("Subscribe to updates", ui.bind("/form/subscribe")),
        ui.ChoicePicker("Colours", "multipleSelection",
            ["Red", "Green", "Blue"], ui.bind("/form/colours"), "chips"),
        ui.Slider("Size", 0, 100, ui.bind("/form/size"), 10),
        ui.DateTimeInput(ui.bind("/form/date"), True, False, label="Date"),
        ui.Button(ui.Text("Submit to Python"), "primary", ui.Event("submit", {
            "name": ui.bind("/form/name"),
            "subscribe": ui.bind("/form/subscribe"),
            "colours": ui.bind("/form/colours"),
            "size": ui.bind("/form/size"),
            "date": ui.bind("/form/date"),
        })),
    ])
    layout = ui.Column([
        section("Row (spaceBetween)", ui.Row(
            [ui.Text("one"), ui.Text("two"), ui.Text("three")], "spaceBetween")),
        section("List (horizontal)", ui.List(
            [ui.Card(ui.Text(f"card {i}")) for i in range(1, 7)], "horizontal")),
        section("Modal", ui.Modal(
            ui.Button(ui.Text("Open modal"), action=ui.Event("modal_opened")),
            ui.Column([ui.Text("Content shown in a modal."),
                       ui.Icon("check")]))),
    ])
    media = ui.Column([
        section("Image", ui.Image(OWL, "An owl", "cover", "mediumFeature")),
        section("Video", ui.Video(BEE)),
        section("AudioPlayer", ui.AudioPlayer(BEE, "Bee audio track")),
    ])
    tabs = ui.Tabs([
        {"title": "Display", "child": display},
        {"title": "Inputs", "child": inputs},
        {"title": "Layout", "child": layout},
        {"title": "Media", "child": media},
    ])
    return ui.Column([ui.Card(ui.Text(note)), tabs])

FORM = {"form": {"name": "Ada", "subscribe": True, "colours": ["Blue"],
                 "size": 40, "date": "2026-11-19"}}

def handle_event(name, context):
    if name == "submit":
        size = context["size"]
        note = (f"Python received {context['name']!r}, size {size} "
                f"({'large' if size > 50 else 'small'}), colours {context['colours']}")
        ui.show(build(note), data=DATA)
    else:
        print("event:", name)

ui.show(build("Fill the form and press Submit."), data=FORM)
"18 basic components rendered"''',
  },
  {
    'label': 'Counter',
    'source': '''
import ui

state = {"count": 0, "history": []}

def render():
    n = state["count"]
    ui.show(ui.Card(ui.Column([
        ui.Text(f"Count: {n}"),
        ui.Text("#" * n if n > 0 else "(empty)", "caption"),
        ui.Row([
            ui.Button(ui.Text("-1"), action=ui.Event("dec")),
            ui.Button(ui.Text("+1"), "primary", ui.Event("inc")),
            ui.Button(ui.Text("x2"), action=ui.Event("double")),
            ui.Button(ui.Text("Reset"), "borderless", ui.Event("reset")),
        ], "spaceBetween"),
        ui.Text("history: " + ", ".join(state["history"][-8:]), "caption"),
    ])))

def handle_event(name, context):
    if name == "inc":
        state["count"] += 1
    elif name == "dec":
        state["count"] = max(0, state["count"] - 1)
    elif name == "double":
        state["count"] = min(40, state["count"] * 2)
    else:
        state["count"] = 0
    state["history"].append(name)
    render()

render()''',
  },
  {
    'label': 'Live table',
    'source': '''
import ui

def table(n, sort_desc):
    rows = []
    for i in range(1, n + 1):
        sq = i * i
        rows.append((i, sq, sq % 7, "#" * (sq % 7)))
    if sort_desc:
        rows = sorted(rows, key=lambda r: (-r[2], r[0]))
    header = ui.Row([ui.Text(h, "caption") for h in ["i", "i*i", "mod 7", "bar"]],
                    "spaceBetween")
    body = [ui.Row([ui.Text(str(c)) for c in r], "spaceBetween") for r in rows]
    return ui.Column([
        ui.Slider("Rows", 1, 20, ui.bind("/n"), 19),
        ui.CheckBox("Sort by mod 7", ui.bind("/sort")),
        ui.Button(ui.Text("Recompute in Python"), "primary",
                  ui.Event("recompute", {"n": ui.bind("/n"), "sort": ui.bind("/sort")})),
        ui.Divider(),
        header,
    ] + body)

def handle_event(name, context):
    n = int(context["n"])
    ui.show(table(n, context["sort"]), data={"n": n, "sort": context["sort"]})

ui.show(table(6, False), data={"n": 6, "sort": False})''',
  },
  {
    'label': 'Primes',
    'source': '''
def primes_up_to(n):
    sieve = [True] * (n + 1)
    sieve[0] = sieve[1] = False
    for i in range(2, int(n ** 0.5) + 1):
        if sieve[i]:
            for j in range(i * i, n + 1, i):
                sieve[j] = False
    return [i for i, is_prime in enumerate(sieve) if is_prime]

ps = primes_up_to(200)
twins = [(p, p + 2) for p in ps if p + 2 in ps]
print(f"{len(ps)} primes below 200, largest {ps[-1]}")
print("twin primes:", twins[:8])
sum(ps)''',
  },
  {
    'label': 'Mandelbrot',
    'source': '''
def mandel(cx, cy, limit=30):
    x, y = 0.0, 0.0
    for i in range(limit):
        x, y = x * x - y * y + cx, 2 * x * y + cy
        if x * x + y * y > 4:
            return i
    return limit

shades = " .:-=+*#%@"
for row in range(22):
    line = ""
    for col in range(64):
        n = mandel(-2.2 + col * 0.05, -1.1 + row * 0.1)
        line += shades[min(n * len(shades) // 30, len(shades) - 1)]
    print(line)''',
  },
  {
    'label': 'Game of Life',
    'source': '''
def step(cells):
    counts = {}
    for (r, c) in cells:
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if dr or dc:
                    key = (r + dr, c + dc)
                    counts[key] = counts.get(key, 0) + 1
    return {k for k, n in counts.items() if n == 3 or (n == 2 and k in cells)}

def show(cells, size=8):
    for r in range(size):
        print("".join("#" if (r, c) in cells else "." for c in range(size)))

glider = {(0, 1), (1, 2), (2, 0), (2, 1), (2, 2)}
for gen in range(4):
    print(f"generation {gen}")
    show(glider)
    glider = step(glider)''',
  },
  {
    'label': 'Sales report',
    'source': '''
sales = [
    ("North", "Q1", 1200), ("South", "Q1", 950), ("North", "Q2", 1430),
    ("East", "Q1", 610), ("South", "Q2", 1100), ("East", "Q2", 880),
    ("North", "Q3", 1610), ("South", "Q3", 1240), ("East", "Q3", 930),
]
quarters = sorted({q for _, q, _ in sales})
table = {}
for region, quarter, amount in sales:
    table.setdefault(region, {})[quarter] = amount

print(f"{'Region':<8}" + "".join(f"{q:>8}" for q in quarters) + f"{'Total':>9}")
for region in sorted(table, key=lambda r: -sum(table[r].values())):
    row = table[region]
    print(f"{region:<8}" + "".join(f"{row.get(q, 0):>8}" for q in quarters)
          + f"{sum(row.values()):>9}")
best = max(sales, key=lambda s: s[2])
f"best: {best[0]} {best[1]} ({best[2]})"''',
  },
  {
    'label': 'Word counts',
    'source': '''
text = """It was the best of times, it was the worst of times,
it was the age of wisdom, it was the age of foolishness,
it was the epoch of belief, it was the epoch of incredulity."""

words = []
for raw in text.lower().split():
    word = "".join(ch for ch in raw if ch.isalpha())
    if word:
        words.append(word)

counts = {}
for w in words:
    counts[w] = counts.get(w, 0) + 1

top = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:6]
for word, n in top:
    print(f"{word:>12} {'#' * n} {n}")
f"{len(words)} words, {len(counts)} distinct"''',
  },
  {
    'label': 'Matrices',
    'source': '''
def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(len(b)))
             for j in range(len(b[0]))] for i in range(len(a))]

def det(m):
    if len(m) == 1:
        return m[0][0]
    total = 0
    for col in range(len(m)):
        minor = [row[:col] + row[col + 1:] for row in m[1:]]
        total += (-1) ** col * m[0][col] * det(minor)
    return total

a = [[2, 0, 1], [1, 3, 2], [1, 1, 2]]
b = [[1, 2, 0], [0, 1, 1], [2, 0, 3]]
for row in matmul(a, b):
    print(row)
print("transpose:", [list(col) for col in zip(*a)])
det(a), det(matmul(a, b))''',
  },
  {
    'label': 'Errors',
    'source': '''
def parse_age(text):
    value = int(text)
    if value < 0 or value > 150:
        raise ValueError(f"age out of range: {value}")
    return value

results = []
for raw in ["42", "-3", "abc", "200", "7"]:
    try:
        results.append(("ok", parse_age(raw)))
    except ValueError as e:
        results.append(("error", str(e)))
    finally:
        pass

for status, detail in results:
    print(f"{status:<6} {detail}")
sum(d for s, d in results if s == "ok")''',
  },
];
