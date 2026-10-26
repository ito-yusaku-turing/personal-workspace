import json,glob,sys
def load(p):
    x=json.load(open(p)); return json.loads(x) if isinstance(x,str) else x
def strip(r):
    r=dict(r); r.pop("Metadata",None); return r
def res(spec,a):
    if spec=="deployed": return load(f"deployed/{a}.json")["Resources"]
    return json.load(open(glob.glob(f"{spec}/{a}/*.template.json")[0]))["Resources"]
x,y=sys.argv[1],sys.argv[2]
for a in ["datalake","gaming-data-collection","denso-taxi","denso-nx"]:
    A=res(x,a);B=res(y,a)
    d=[k for k in sorted(set(A)|set(B)) if k!="CDKMetadata" and (k not in A or k not in B or strip(A[k])!=strip(B[k]))]
    print(f"{a}: {x} → {y} の差 {len(d)} 件", d)
