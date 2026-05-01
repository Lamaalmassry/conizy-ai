# Bedrock Chat Infra (Terraform)

هذا المجلد ينشئ:
- Lambda Function (Node.js 20)
- IAM Role + صلاحيات Bedrock invoke
- Lambda Function URL مع CORS
- الربط مع أرخص موديل افتراضيًا: `amazon.nova-micro-v1:0`

## المتطلبات
- Terraform `>= 1.6`
- AWS credentials مفعلة محليًا (`aws configure`)
- Bedrock model access مفعل لـ Nova Micro داخل نفس الـ region

## تشغيل

```bash
cd infra/bedrock-chat
terraform init
terraform apply -auto-approve
```

بعد التنفيذ، خذي قيمة:
- `lambda_function_url`

وضعّيها في التطبيق داخل:
- `_ConizyAiService._endpoint` في `lib/main.dart`

## اختبار سريع

```bash
curl -X POST "<LAMBDA_FUNCTION_URL>" \
  -H "content-type: application/json" \
  -d "{\"message\":\"اعطني نصيحة مالية سريعة\"}"
```

## تدمير الموارد

```bash
terraform destroy -auto-approve
```
