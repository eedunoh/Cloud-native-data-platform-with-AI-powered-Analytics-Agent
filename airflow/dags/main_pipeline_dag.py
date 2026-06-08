# Import the necessary libraries
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator
from datetime import datetime, timedelta
import os
import sys

# Airflow needs to locate the ingestion scripts. 
# /opt/airflow is where we mount our project files inside the airflow container. It simply tells Python: "When looking for modules to import, start from the root folder (/opt/airflow)"
sys.path.append('/opt/airflow')


# Next, we import our ingestion scripts
# PS: ingestion.batch.batch_ingestor.py is a module. The run function is imported from each ingestion script/module.
# The PythonOperator will execute these functions as Airflow tasks.

# We write "from ingestion.batch.batch_ingestor import run as run_batch" instead of using a shell command like "python3 batch_ingestor.py" because Airflow’s PythonOperator runs Python functions directly, not shell commands. 
# This gives you much more control and reliability.

from ingestion.batch.batch_ingestor import run as run_batch
from ingestion.documents.doc_extractor import run as run_doc_extractor


# We will define default arguments applied to every task in the DAG
# We add start_date becasuse Airflow needs a reference point. Basically, "When did this DAG life begin?". This will help it track how many runs, how long since last run and is it overdue for a run?
# Never use datetime.now() as startdate. As it updates every second could confuse airflow about reference point. 

default_args = {
    'owner': 'data_platform',
    'depends_on_past': False,
    'start_date': datetime(2026,1,1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5)   
}


# Define DAG
# Setting catchup=False, Airflow ignores all missed runs and runs from now forward. The catup parameter works with start_date parameter.
# catchup=True will retry all missed runs. This is compute heavy and could kill your server or ec2
# Best practice is to set start_date to a a recent date and always use catchup=False. 

with DAG(
    dag_id='main_pipeline_dag',
    default_args=default_args,
    description='Main dataplatform airflow pipeline',
    schedule_interval=timedelta(minutes=15),
    catchup=False,
    tags=['data_platform']
) as dag:
    
    # start defining tasks
    # Task: Start with an Empty Operator. It has no logic and does nothing but helps alot with regards to visual representation of the Airflow stages when viewd on the UI

    start = EmptyOperator(
        task_id='Start'
    )


    # Task: Call run() from the batch_ingestor.py script. PythonOperator executes a python function in an airflow Task
    batch_ingestion = PythonOperator(
        task_id='Process batch data'
        python_callable=run_batch
    )


    # Task: Call run() from the doc_extractor.py script
    document_extraction = PythonOperator(
        task_id='Extract_documents using Claude AI'
        python_callable=run_doc_extractor
    )

    
    # Task: End with an Empty Operator. It also has no logic and does nothing but helps alot with regards to visual representation of the Airflow stages when viewd on the UI
    end = EmptyOperator(
        task_id = 'End'
    )


    # Define task dependencies. This is what creates the DAG structure, It tells how the DAG should run
    start >> [batch_ingestion, document_extraction] >> end