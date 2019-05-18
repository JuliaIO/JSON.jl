from functools import reduce
from textwrap import dedent as dd
from timeit import repeat


sources = ["canada", "citm_catalog", "citylots", "twitter"]

min_times = []
for source in sources:
    s = dd(f"""\
    with open("../data/{source}.json") as f:
        json.load(f)""")
    times = repeat(stmt=s, setup="import json", repeat=3, number=1)
    t = reduce(min, times)
    print(f"{source} {t:0.06f} seconds")
    min_times.append(t)

geo_mean = reduce(lambda a, b: a*b, min_times)**(1/len(min_times))
print(f"Total (G.M): {geo_mean:0.06f}")
