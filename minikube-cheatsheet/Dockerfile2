FROM python:3.9-slim

RUN mkdir /app
WORKDIR /app
ADD . /app/
# COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Expose port 8080 to the outside world
EXPOSE 5000

# CMD ["python", "app.py"]
# CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
