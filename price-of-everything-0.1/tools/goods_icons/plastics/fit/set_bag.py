import json, re, sys
G = json.load(open(sys.argv[1])); G.setdefault('pe', 2.4); note = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
s = open('source/plastics_kit.py').read()
body = ', '.join("%s=%s" % (k, repr(round(float(v), 4))) for k, v in G.items())
s = re.sub(r"# v6: fitted to the shipped bag's silhouette.*?\nBAG = dict\(.*?\)\n", "# v6: fitted to the shipped bag's silhouette (%s)\nBAG = dict(%s)\n" % (note, body), s, flags=re.S)
open('source/plastics_kit.py', 'w').write(s)
