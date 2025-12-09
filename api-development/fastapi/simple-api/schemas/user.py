from typing import Optional
from pydantic import (BaseModel, 
                       EmailStr, 
                       Field, 
                       field_validator, 
                       ConfigDict,
                       validator)
from .base import BaseSchema, TimestampedSchema

class UserBase(BaseSchema):
  """Base schema for all users

  Args:
      BaseSchema (_type_): _description_
  """
  username: str
  email: EmailStr
  full_name: Optional[str] = None
  is_active: bool = True
  is_superuser: bool = False

class UserCreate(UserBase):
  """Schema for creating a new user

  Args:
      UserBase (_type_): _description_
  """
  password: str = Field(..., min_length=8, max_length=100)  

  @field_validator('password')
  @classmethod
  def validate_password(cls, v: str) -> str:
    """Validate the password

    Args:
      v (_type_): _description_
    """
    if not any(char.isdigit() for char in v):
      raise ValueError("Password must contain at least one number")
    if not any(char.isalpha() for char in v):
      raise ValueError("Password must contain at least one letter")
    if not any(char.isupper() for char in v):
      raise ValueError("Password must contain at least one uppercase letter")
    if not any(char.islower() for char in v):
      raise ValueError("Password must contain at least one lowercase letter")
    return v


class UserUpdate(BaseSchema):
  """Schema for updating an existing user

  Args:
      BaseSchema (_type_): _description_
  """
  username: Optional[str] = Field(None, min_length=1, max_length=255)
  email: Optional[EmailStr] = Field(None, format="email")
  full_name: Optional[str] = Field(None, max_length=100)
  is_active: Optional[bool] = None
  is_superuser: Optional[bool] = None

class UserInDB(UserBase, TimestampedSchema):
  """Schema for a user in the database

  Args:
      UserBase (_type_): _description_
      TimestampedSchema (_type_): _description_
  """
  hashed_password: str

class User(UserBase, TimestampedSchema):
  """Schema for a single user

  Args:
      UserBase (_type_): _description_
      TimestampedSchema (_type_): _description_
  """
  pass

class UserWithItems(User):
  """Schema for a single user with items

  Args:
      User (_type_): _description_
  """
  items: List["ItemInUser"] = []


class ItemInUser(BaseSchema):
  """Schema for an item in a user

  Args:
      BaseSchema (_type_): _description_
  """
  id: int
  title: str
  description: Optional[str] = None
  price: Optional[float] = None
  is_available: bool = True