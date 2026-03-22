from flask import Flask, jsonify, send_from_directory
import os

app = Flask(__name__)

@app.route('/ui')
def ui():
    return send_from_directory('static', 'index.html')

@app.route('/')
def home():
    return jsonify({
        'message': 'API DevOps - Master DSBD & IA',
        'version': os.getenv('APP_VERSION', '1.0.0'),
        'status': 'running'
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
