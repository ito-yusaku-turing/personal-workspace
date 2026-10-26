import json,fnmatch,collections,sys
d=json.load(open('iam.json'))
B=[l.strip() for l in open('buckets.txt') if l.strip()]
OBJ=["s3:DeleteObjectVersion","s3:DeleteObject","s3:PutObject"]
pol={p['Arn']:[v for v in p['PolicyVersionList'] if v['IsDefaultVersion']][0]['Document'] for p in d['Policies']}
def L(x): return x if isinstance(x,list) else [x]
def am(pats,a): return any(fnmatch.fnmatchcase(a.lower(),p.lower()) for p in pats)
def covers_some_object(p,b):
    # p の Resource が、バケット b の「何らかの」オブジェクトに当たりうるか
    if not p.startswith('arn:aws:s3:::') and p!='*': return False
    if p=='*': return True
    rest=p[len('arn:aws:s3:::'):]
    if fnmatch.fnmatchcase(b+'/x',rest): return True
    if '/' in rest:
        bp=rest.split('/',1)[0]
        return fnmatch.fnmatchcase(b,bp)
    return False
def stmts(e):
    for ip in e.get('RolePolicyList',[])+e.get('UserPolicyList',[]): yield ('inline:'+ip['PolicyName'],ip['PolicyDocument'])
    for ap in e.get('AttachedManagedPolicies',[]): yield (ap['PolicyName'],pol[ap['PolicyArn']])
res=[]
for e in d['RoleDetailList']+d['UserDetailList']:
    for name,doc in stmts(e):
        if isinstance(doc,str): doc=json.loads(doc)
        for s in L(doc['Statement']):
            if s['Effect']!='Allow': continue
            acts=[a for a in OBJ if ('Action' in s and am(L(s['Action']),a)) or ('NotAction' in s and not am(L(s['NotAction']),a))]
            if not acts: continue
            if 'NotResource' in s: res.append((e['Arn'],name,acts,'NotResource',s['NotResource'])); continue
            for r in L(s['Resource']):
                for b in B:
                    rest=r[len('arn:aws:s3:::'):] if r.startswith('arn:aws:s3:::') else None
                    if covers_some_object(r,b) and not (rest is not None and fnmatch.fnmatchcase(b+'/x',rest)) and r!='*':
                        res.append((e['Arn'].split(':')[-1],name,acts,b,r,bool(s.get('Condition'))))
for x in res: print(x)
print(len(res),'prefix-scoped grants')
