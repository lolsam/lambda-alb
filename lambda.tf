#--------------Lambda Role for Cstools ALB/NLB ip------------------------------

resource "aws_iam_role" "role-lambda" {
  name               = "${var.environment}-lambda-alb-role"
  assume_role_policy = file("./role/lambda-role.json")
}

resource "aws_iam_policy" "lambda-service-policy" {
  name   = "${var.environment}-lambda-alb-service-policy"
  policy = file("./policy/lambda-policy.json")
}

resource "aws_iam_role_policy_attachment" "attach-lambda-role" {
  role       = aws_iam_role.role-lambda.name
  policy_arn = aws_iam_policy.lambda-service-policy.arn
}

#----------------------Function----------------------------

resource "aws_lambda_function" "static_lb_updater" {
  filename      = "lambda_function.zip"
  function_name = "cstools-alb-nlb"
  description   = "Updates Cstools load balancer IPs"
  role          = aws_iam_role.role-lambda.arn
  handler       = "populate_NLB_TG_with_ALB.lambda_handler"

  source_code_hash = filebase64sha256("lambda_function.zip")

  runtime     = "python2.7"
  memory_size = 128
  timeout     = 300

  environment {
    variables = {
      ALB_DNS_NAME                      = aws_lb.lb-internal.dns_name
      ALB_LISTENER                      = "443"
      S3_BUCKET                         = var.cstools_lambda.bucket
      NLB_TG_ARN                        = var.cstools_lambda.tg
      MAX_LOOKUP_PER_INVOCATION         = 50
      INVOCATIONS_BEFORE_DEREGISTRATION = 10
      CW_METRIC_FLAG_IP_COUNT           = true
    }
  }
}

resource "aws_cloudwatch_event_rule" "cron_minute" {
  name                = "cron-minute-lambda"
  schedule_expression = "rate(1 minute)"
  is_enabled          = true
}

resource "aws_cloudwatch_event_target" "static_lb_updater" {
  rule      = aws_cloudwatch_event_rule.cron_minute.name
  target_id = "TriggerStaticPort"
  arn       = aws_lambda_function.static_lb_updater.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.static_lb_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron_minute.arn
