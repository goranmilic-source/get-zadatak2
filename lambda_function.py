import os
import boto3

# Created outside the handler so warm invocations reuse the client.
sns = boto3.client("sns")


def lambda_handler(event, context):
    response = sns.publish(
        TopicArn=os.environ["TOPIC_ARN"],
        Subject="Daily message",
        Message="Hello, world!",
    )
    return {"messageId": response["MessageId"]}