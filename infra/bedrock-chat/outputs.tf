output "lambda_function_name" {
  value       = aws_lambda_function.chat.function_name
  description = "Created Lambda function name."
}

output "lambda_function_url" {
  value       = aws_lambda_function_url.chat_url.function_url
  description = "Public URL for Flutter app endpoint."
}

output "bedrock_model_id" {
  value       = var.model_id
  description = "Model used by Lambda (Nova Micro by default)."
}
