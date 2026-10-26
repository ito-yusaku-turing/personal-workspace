# PR の synth から 12 本の最終ポリシーを取り出し、アカウント・論理 ID を具体値に直して書き出す
import json,glob,os
ACC="767397804933"
B2N={"RawBucket0C3EE094":"td1-raw-"+ACC,"TuscenesRawBucket4AB05826":"tuscenes-raw-"+ACC,"TuscenesCalibrationBucketC3E06279":"tuscenes-calibration-"+ACC,
"TuscenesAnnotationBucket6D773481":"tuscenes-annotation-"+ACC,"Bucket83908E77":"gaming-data-collection-"+ACC,
"DensoTaxiProcessedBucketF7F9B1F7":None,"DensoNxBucket":None}
def r(x,res):
    if isinstance(x,dict):
        if "Fn::Join" in x: return x["Fn::Join"][0].join(r(i,res) for i in x["Fn::Join"][1])
        if x.get("Ref")=="AWS::AccountId": return ACC
        if x.get("Ref")=="AWS::Partition": return "aws"
        if "Ref" in x: return r(res[x["Ref"]]["Properties"]["BucketName"],res) if "BucketName" in res[x["Ref"]]["Properties"] else x["Ref"]
        if "Fn::GetAtt" in x: return "arn:aws:s3:::"+r(res[x["Fn::GetAtt"][0]]["Properties"]["BucketName"],res)
        return {k:r(v,res) for k,v in x.items()}
    if isinstance(x,list): return [r(i,res) for i in x]
    return x
os.makedirs("final",exist_ok=True)
for a in ["datalake","gaming-data-collection","denso-taxi","denso-nx"]:
    res=json.load(open(glob.glob(f"pr2c/{a}/*.template.json")[0]))["Resources"]
    for k,v in res.items():
        if v["Type"]!="AWS::S3::BucketPolicy": continue
        doc=v["Properties"]["PolicyDocument"]
        if not any(s.get("Sid")=="DenyIrreversibleDelete" for s in doc["Statement"]): continue
        name=r(v["Properties"]["Bucket"],res)
        json.dump(r(doc,res),open(f"final/{name}.json","w"),indent=2)
        print(name)
