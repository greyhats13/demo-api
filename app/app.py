from flask import Flask
import os

app = Flask(__name__)

# Connection settings for a downstream datastore.
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "SuperSecret123!")


@app.route("/")
def index():
    return {"message": "Hello from the API", "version": "1.0.0"}


@app.route("/health")
def health():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
