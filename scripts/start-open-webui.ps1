# เริ่ม Open WebUI (ถูกเรียกโดย Task Scheduler ตอนเครื่องบูต ไม่ต้องรันเอง)
. "$PSScriptRoot\common.ps1"
$cfg = Read-AiConfig

$env:DATA_DIR            = Join-Path $AiRoot 'open-webui\data'
$env:HF_HOME             = Join-Path $AiRoot 'hf-cache'     # ที่เก็บโมเดล embedding / reranker
$env:PYTHONIOENCODING    = 'utf-8'
$env:WEBUI_SECRET_KEY    = $cfg.SecretKey
$env:WEBUI_URL           = $cfg.WebUIUrl

# เชื่อมกับ LM Studio (API แบบ OpenAI ที่ 127.0.0.1:1234 ในเครื่องเดียวกัน)
$env:ENABLE_OLLAMA_API   = 'false'
$env:OPENAI_API_BASE_URL = 'http://127.0.0.1:1234/v1'
$env:OPENAI_API_KEY      = 'lm-studio'                    # LM Studio ไม่ตรวจ key ใส่ค่าอะไรก็ได้

# ค่าด้านล่างมีผลแค่ตอนเริ่มครั้งแรก หลังจากนั้นแก้ที่ Admin Settings
$env:ENABLE_SIGNUP            = 'true'                    # บัญชีแรกที่สมัครจะเป็น admin
$env:DEFAULT_USER_ROLE        = 'pending'                 # คนอื่นต้องรอ admin อนุมัติ
$env:RAG_EMBEDDING_MODEL      = 'BAAI/bge-m3'             # รองรับภาษาไทย
$env:ENABLE_RAG_HYBRID_SEARCH = 'true'
$env:RAG_RERANKING_MODEL      = 'BAAI/bge-reranker-v2-m3'

$exe = Join-Path $AiRoot 'open-webui\venv\Scripts\open-webui.exe'
$log = Join-Path $LogDir 'open-webui.log'
& $exe serve --host 0.0.0.0 --port 3000 *>> $log
