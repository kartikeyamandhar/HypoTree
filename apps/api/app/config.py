from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    anthropic_api_key: str = ""
    openai_api_key: str = ""
    database_url: str = "postgresql+asyncpg://hypotree:hypotree@localhost:5432/hypotree"
    redis_url: str = "redis://localhost:6379/0"
    serp_api_key: str = ""
    alpha_vantage_api_key: str = ""
    langsmith_api_key: str = ""
    langsmith_project: str = "hypotree"
    environment: str = "development"
    log_level: str = "INFO"
    cors_origins: str = "http://localhost:5173"

    class Config:
        env_file = ".env"


settings = Settings()
