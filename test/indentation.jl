# check indented json has same final value as non indented
fb = JSON.parse(Typ(facebook))
fbjson1 = json(fb, 2)
fbjson2 = json(fb)
@test JSON.parse(Typ(fbjson1)) == JSON.parse(Typ(fbjson2))

ev = JSON.parse(Typ(svg_tviewer_menu))
ejson1 = json(ev, 2)
ejson2 = json(ev)
@test JSON.parse(Typ(ejson1)) == JSON.parse(Typ(ejson2))
