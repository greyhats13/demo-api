FROM python:latest

WORKDIR /app

COPY . .

RUN pip install -r app/requirements.txt

ENV DB_PASSWORD=SuperSecret123!

EXPOSE 8080

CMD ["python", "app/app.py"]
