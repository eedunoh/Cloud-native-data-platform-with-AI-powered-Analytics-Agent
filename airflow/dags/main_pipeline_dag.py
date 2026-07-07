# Import the necessary libraries
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.sensors.time_delta import TimeDeltaSensor
from datetime import datetime, timedelta
import os
from os import environ
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



# Next, define dbt_project and dbt_profile folders. 
# These paths are gotten from mounted volumes in the airflow docker-compose file. I've added comments to explain how I derived these paths
DBT_PROFILE_DIR = '/opt/dbt_profile'
DBT_PROJECT_DIR ='/opt/dbt_project'



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
    description='Main_dataplatform_airflow_pipeline',
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
        task_id='Process_batch_data',
        python_callable=run_batch
    )


    # Task: Call run() from the doc_extractor.py script
    document_extraction = PythonOperator(
        task_id='Extract_documents_using_Claude_AI',
        python_callable=run_doc_extractor
    )

    # Task: Wait for 5 minutes
    wait_buffer = TimeDeltaSensor(
        task_id='Wait_for_5_minutes',
        delta=timedelta(minutes=5),
        mode='reschedule',          # frees up the worker slot while waiting
    )


# If you notice, the way I define the DBT_PASSWORD variable is different compared to how I defined ANTHROPIC_API_KEY variable in the document_extraction script.

# In document_extraction script, I used Variable.get("ANTHROPIC_API_KEY") in the script and then add the value in airflow variable UI. This worked because Airflow directly runs that Python code, so the Airflow Variable store is available.

# For the profile.yml PASSWORD and ACCOUNT case, we set the variable in the yml file and then expose (define) it again in the DAG for airflow to see. ONLY then will Airflow Variable store be available.
# Airflow does not directly use the password and account. DBT uses the password and account. So variable definition here will be different compared to the case above.

    dbt_build = BashOperator(
        task_id='Install_dbt_packages_and_run_dbt_build',

        # Airflow uses double curly braces {{ ... }} for its own templates 
        # env = {
        #     **environ,
        #     'DB_ACCOUNT': '{{ var.value.DB_ACCOUNT }}',
        #     'DB_PASSWORD': '{{ var.value.DB_PASSWORD }}'

        # },

        bash_command = (
            "dbt deps --project-dir /opt/dbt_project 2>&1 && "
            "dbt build --target prod --profiles-dir /opt/dbt_profile --project-dir /opt/dbt_project 2>&1"
        )
    )

    
    # Task: End with an Empty Operator. It also has no logic and does nothing but helps alot with regards to visual representation of the Airflow stages when viewd on the UI
    end = EmptyOperator(
        task_id = 'End'
    )


    # Define task dependencies. This is what creates the DAG structure, It tells how the DAG should run
    # This means batch_ingestion and document_extraction are run simultaneously and must complete before dbt_build run.
    start >> [batch_ingestion, document_extraction] >> wait_buffer >> dbt_build >> end



# IMPORTANT!!! 

# TROUBLESHOOTING 1

# I encountered a "dbt: command not found" error while running the dbt_build task in Airflow. 
# Although dbt was correctly installed inside the Airflow container (verified using docker "exec airflow_scheduler dbt --version" and "which dbt"), the Bash process launched by the BashOperator could not locate the executable.

# The root cause was the use of the env parameter in the BashOperator. 
# By defining only DB_ACCOUNT and DB_PASSWORD in the env dictionary, Airflow launched the Bash process with only those two environment variables instead of inheriting the container's default environment. 
# Consequently, important variables such as PATH, HOME, USER, and AIRFLOW_HOME were not available to the task. 
# Since Bash relies on the PATH environment variable to locate executables, it had no way of finding the installed dbt binary, resulting in the "dbt: command not found" error.

# The recommended solution is to preserve the existing environment by including "os.environ" when defining env. "os.environ" is simply a dictionary containing the current environment variables. 
# By merging it with the custom variables, the task retains all the default environment variables (including PATH, HOME etc.) while also receiving DB_ACCOUNT and DB_PASSWORD. 
# An alternative approach is to manually redefine PATH and other required environment variables, but this is less maintainable and more error-prone.

# Another potential cause of this error is how dbt is installed in the Docker image. 
# Installing Python packages with "pip install --user" places executables in a user-specific directory such as /home/airflow/.local/bin, whereas installing them as the root user typically places them in a standard system directory such as /usr/local/bin. 
# The latter is generally more robust because system directories are more commonly included in the default PATH. 

# However, in this case, the installation location was not the root cause. The actual issue was that the PATH environment variable was not passed to the Bash process.



# Troubleshooting order:
# First, verify whether the BashOperator is overriding the environment using the env parameter and ensure the existing environment (especially PATH) is preserved.
# If the environment is correct, then investigate where dbt was installed in the Docker image (--user vs. system-wide installation) and confirm that the executable is located in a directory included in PATH.




# TROUBLESHOOTING 2

# When saving the profiles.yml file, save it as profiles.yml NOT profile.yml. One has an "s" and the other doesn't. 
# DBT expect the profiles with an "s"
# If there is no "s" in the profiles, you will get an error and the airflow task will fail