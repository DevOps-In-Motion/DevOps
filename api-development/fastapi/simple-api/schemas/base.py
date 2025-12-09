from datetime import datetime
from typing import Optional
from pydantic import BaseModel



class BaseSchema(BaseModel):
  """Base schema for all schemas

  Args:
      BaseModel (_type_): _description_
  """
  model_config = ConfigDict(
    from_attributes = True  # This allows the schema ORM mode (if using SQLAlchemy)
    populate_by_name = True  
    use_enum_values = True  
    arbitrary_types_allowed = True
  )


class TimestampedSchema(BaseSchema):
  """Timestamped schema for all schemas

  Args:
      BaseSchema (_type_): _description_
  """
  id: int
  created_at: datetime
  updated_at: datetime