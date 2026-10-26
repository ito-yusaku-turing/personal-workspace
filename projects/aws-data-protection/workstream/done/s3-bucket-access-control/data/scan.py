import json,fnmatch,collections,sys
d=json.load(open('iam.json'))
B=[l.strip() for l in open('buckets.txt') if l.strip()]
ACTS=["s3:DeleteObjectVersion","s3:DeleteObject","s3:PutObject","s3:PutBucketVersioning","s3:PutLifecycleConfiguration","s3:PutBucketPolicy","s3:DeleteBucketPolicy","s3:PutBucketObjectLockConfiguration","s3:DeleteBucket"]
RES=[f"arn:aws:s3:::{b}" for b in B]+[f"arn:aws:s3:::{b}/x" for b in B]
pol={p['Arn']:[v for v in p['PolicyVersionList'] if v['IsDefaultVersion']][0]['Document'] for p in d['Policies']}
def L(x): return x if isinstance(x,list) else [x]
def m(pats,vals): return any(fnmatch.fnmatchcase(v.lower(),p.lower()) for p in pats for v in vals)
def stmts(e):
    for ip in e.get('RolePolicyList',[])+e.get('UserPolicyList',[]): yield ('inline:'+ip['PolicyName'],ip['PolicyDocument'])
    for ap in e.get('AttachedManagedPolicies',[]):
        if ap['PolicyArn'] not in pol: print('MISSING',ap['PolicyArn'],file=sys.stderr); continue
        yield (ap['PolicyName'],pol[ap['PolicyArn']])
out=collections.defaultdict(list)
for e in d['RoleDetailList']+d['UserDetailList']:
    for name,doc in stmts(e):
        if isinstance(doc,str): doc=json.loads(doc)
        for s in L(doc['Statement']):
            if s['Effect']!='Allow' or 'Condition' not in s: continue
            acts=[a for a in ACTS if ('Action' in s and m(L(s['Action']),[a])) or ('NotAction' in s and not m(L(s['NotAction']),[a]))]
            if not acts: continue
            if 'Resource' in s and not m(L(s['Resource']),RES): continue
            if 'NotResource' in s and all(m(L(s['NotResource']),[r]) for r in RES): continue
            out[json.dumps(s['Condition'],sort_keys=True)].append((e['Arn'].split('/')[-1],name,len(acts)))
for c,v in sorted(out.items(),key=lambda x:-len(x[1])):
    print(len(v),c[:300]); print('   ',sorted(set(x[1] for x in v))[:6], sorted(set(x[0] for x in v))[:4])
