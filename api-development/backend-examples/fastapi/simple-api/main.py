from fastapi import (FastAPI,
                     Response,
                     status,
                     HTTPException)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from api.routes import router

from core.config import settings
from api.routes import router

app = FastAPI()
app.include_router(router)

async def lifespan(app: FastAPI):
  """Lifespan for the application

  Args:
      app (FastAPI): The FastAPI application
  """
  print("Starting up...")
  await asyncio.sleep(10)
  # add database connection here
  print("Database connection established")
  yield
  # close database connection here
  print("Database connection closed")
  await asyncio.sleep(10)
  # add database connection here
  print("Database connection established")
  yield
  # close database connection here
  print("Database connection closed")
  yield
  print("Shutting down...")

app FastAPI(
  title=settings.PROJECT_NAME,
  description=settings.PROJECT_DESCRIPTION,
  version=settings.PROJECT_VERSION,
  lifespan=lifespan,
  docs_url="/docs",
  redoc_url="/redoc",
  openapi_url="/openapi.json",
)

app.add_middleware(
  CORSMiddleware,
  allow_origins=settings.CORS_ALLOW_ORIGINS,
  allow_credentials=True,
  allow_methods=["*"],
  allow_headers=["*"],
)

if settings.ENVIRONMENT == "production":
  app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.TRUSTED_HOSTS,
  )

app.get("/", tags=["root"])
async def read_root():
  """root endpoint - health check

  Returns:
      JSONResponse: JSON response with a message
  """
  return {
    "message": "If you are seeing this, the API is working!",
    "timestamp": datetime.now().isoformat(),
    "version": settings.PROJECT_VERSION,
    "docs": f"{settings.API_URL}/docs",
    "redoc": f"{settings.API_URL}/redoc",
    
  }


app.get("/health", tags=["health"])
async def health_check():
  """health check endpoint - health check

  Returns:
      JSONResponse: JSON response with a message
  """
  return {
    "status": "healthy",
    "environment": settings.ENVIRONMENT,
  }

app.include_router(
  router,
  prefix="/api")


  app.exception_handler(Exception)
  async def global_exception_handler(request, exc):
    """Global exception handler

    Args:
        request (Request): The request object
        exc (Exception): The exception object

    Returns:
        JSONResponse: JSON response with a message
    """
    return JSONResponse(
      status_code=500,
      content={
        "status": "error",
        "message": str(exc) if settings.ENVIRONMENT == "development" else "An unexpected error occurred" != "production" else "An unexpected error occurred",
      },
    )

if __name__ == "__main__":
  import uvicorn
  uvicorn.run(
    "app.main:app", 
    host="0.0.0.0", 
    port=8000, 
    reload=true if settings.ENVIRONMENT == "development" else false
    )