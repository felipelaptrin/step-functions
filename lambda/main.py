import io
import os

import boto3
from PIL import Image

s3 = boto3.client('s3', region_name=os.getenv("AWS_REGION", "us-east-1"))

def resize_image_s3(
    bucket_name: str,
    input_key: str,
    output_key: str,
    size: int
) -> None:
    print("Downloading uploaded profile picture...")
    response = s3.get_object(Bucket=bucket_name, Key=input_key)
    image_data = response['Body'].read()

    print(f"Resizing image to {size}x{size}...")
    image = Image.open(io.BytesIO(image_data))
    image_resized = image.resize((size, size))
    buffer = io.BytesIO()
    image_resized.save(buffer, format=image.format)
    buffer.seek(0)

    print("Uploading resized profile picture to S3...")
    s3.put_object(
        Bucket=bucket_name,
        Key=output_key,
        Body=buffer,
        ContentType=response['ContentType']
    )

def lambda_handler(event, context):
    print(f"{event = }")
    print(f"{context = }")

    try:
        bucket_name = event["body"]["s3"]["bucket"]["name"]
        size = event["size"]
        uploaded_profile_picture_key = event["body"]["s3"]["object"]["key"]
        picture_name = uploaded_profile_picture_key.split("/")[-1]
        user_id = picture_name.split(".png")[0]
        resized_profile_picture_key = f"{user_id}/{size}.png"

        resize_image_s3(
            bucket_name,
            uploaded_profile_picture_key,
            resized_profile_picture_key,
            size
        )
        return {
            "statusCode": 200,
            "data": {
                "message": "Image resized!",
                "userId": user_id,
                "bucket": bucket_name,
                "uploadedKey" : uploaded_profile_picture_key,
                "resizedKey": uploaded_profile_picture_key
            }
        }
    except Exception as e:
        print(e)
        raise Exception(f"Something went wrong: {e}")
