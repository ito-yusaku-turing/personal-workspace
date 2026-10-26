import json,collections,ast,subprocess
d=json.load(open('iam.json')); ent={e['Arn']:e for e in d['RoleDetailList']+d['UserDetailList']}
key=lambda a:a.replace(':','_').replace('/','_')
SH={"s3:DeleteObjectVersion":"版の削除","s3:PutBucketVersioning":"バージョニング","s3:PutLifecycleConfiguration":"ライフサイクル","s3:PutBucketPolicy":"ポリシー","s3:DeleteBucketPolicy":"ポリシー削除","s3:PutBucketObjectLockConfiguration":"Object Lock","s3:DeleteBucket":"バケット削除","s3:DeleteObject":"削除","s3:PutObject":"上書き"}
ORD=list(SH.values())
def bn(b):
    return {'tuscenes-calibration':'calibration(旧)','tuscenes-calibration-767397804933':'calibration(新)'}.get(b,b.replace('-767397804933','').replace('tuscenes-','tu-'))
A=collections.defaultdict(lambda:collections.defaultdict(set)); PFX=collections.defaultdict(set)
for a in open('p59.txt').read().split():
    for s in 'bo':
        for x in json.load(open(f'sim2/{key(a)}.{s}.json')):
            for y in x['r']:
                if y['d']=='allowed': A[a][SH[x['a']]].add(y['r'].split(':::')[1].split('/')[0])
out=subprocess.run(['python3','scan_prefix.py'],capture_output=True,text=True).stdout
for l in out.splitlines():
    if not l.startswith("('"): continue
    p,_,acts,b,r,_c=ast.literal_eval(l); a='arn:aws:iam::767397804933:'+p
    for x in acts:
        if b not in A[a][SH[x]]: A[a][SH[x]].add(b); PFX[a].add(r.split(':::')[1].replace('767397804933','…'))
rows=[]
for a,ops in A.items():
    ops={k:v for k,v in ops.items() if v}
    if not ops: continue
    e=ent[a]; last=(e.get('RoleLastUsed') or {}).get('LastUsedDate','')[:10] if 'RoleName' in e else ''
    tr=e.get('AssumeRolePolicyDocument',{}).get('Statement',[]) if 'RoleName' in e else []
    trust=sorted({str(v).replace('arn:aws:iam::','').replace('.amazonaws.com','').split(':saml')[0] for s in tr for k,vv in s.get('Principal',{}).items() for v in (vv if isinstance(vv,list) else [vv])})
    rows.append(dict(name=a.split(':',5)[5].replace('role/aws-reserved/sso.amazonaws.com/us-west-2/','sso/'),ops={k:sorted(bn(b) for b in v) for k,v in ops.items()},pfx=sorted(PFX[a]),last=last,trust=trust))
json.dump(rows,open('final.json','w'),ensure_ascii=False,indent=1)
print(len(rows))
for r in sorted(rows,key=lambda r:(-len(r['ops']),r['name'])):
    print(r['name'][:60],'|',' '.join(f"{k}{len(r['ops'][k])}" for k in ORD if k in r['ops']),'|',r['pfx'][:3])
