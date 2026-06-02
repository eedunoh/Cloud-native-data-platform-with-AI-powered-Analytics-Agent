import os
import boto3


class Config:
    # Create a dictionary of all sheets to be batch processed
    sheets = {
        'stores': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1732400668&single=true&output=csv'
    ,
        'products': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1116619190&single=true&output=csv'
    ,
        'exchange_rates': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=321208867&single=true&output=csv'
    ,
        'customers': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1182964335&single=true&output=csv'
    ,
        'data_dictionary': 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQY3HBJbC64KzaBHdYRRd7nIdMxbrKPjM3jEKtXiM1VpCM9l_oVYv5WETqKx6GeUZwwaRKhLStS2t1Y/pub?gid=1536678535&single=true&output=csv'

    }


    # Store AWS region in a variable
    aws_region = "eu-north-1"


    # Streaming data set
    streaming_data_set = "https://raw.githubusercontent.com/eedunoh/Cloud-native-data-platform-with-AI-powered-Analytics/main/Sales.csv"


    # Get bucket names from SSM store
    @staticmethod
    def get_ssm_parameter(param_name, with_decryption=True):
        try:
            ssm = boto3.client("ssm", region_name=Config.aws_region)
            response = ssm.get_parameter(Name=param_name, WithDecryption=with_decryption)
            return response["Parameter"]["Value"]
        
        except Exception as e:
            print(f"Warning: Unable to fetch {param_name} from SSM = {e}")
            return None
        
    
    @classmethod
    def initialize(cls):
        cls.streamed_data_bucket = cls.get_ssm_parameter("streaming_bucket")
        cls.batch_bucket = cls.get_ssm_parameter("batch_bucket")
        cls.policy_document_bucket = cls.get_ssm_parameter("policy_document_bucket")
        cls.document_extract_bucket = cls.get_ssm_parameter("document_extract_bucket")
        
        missing = [name for name in ["streamed_data_bucket", "batch_bucket", "policy_document_bucket", "document_extract_bucket"]
                if getattr(cls, name) is None]
        
        if missing:
            raise ValueError(f"Failed to load required SSM parameters: {missing}")



# Explicitly initialize the class variables
Config.initialize()




