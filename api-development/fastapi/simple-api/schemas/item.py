from typing import Optional
from pydantic import Field
from .base import BaseSchema, TimestampedSchema

class ItemBase(BaseSchema):
  """Base schema for all items

  Args:
      BaseSchema (_type_): _description_
  """
  title: str
  description: Optional[str] = None
  price: Optional[float] = Field(None, ge=0, description="Price must be >0")
  is_available: bool = True

class ItemCreate(ItemBase):
  """Schema for creating a new item

  Args:
      ItemBase (_type_): _description_
  """
  pass

class Item(TimestampedSchema, ItemBase):
  """Schema for a single item

  Args:
      TimestampedSchema (_type_): _description_
      ItemBase (_type_): _description_
  """
  owner_id: int

class ItemUpdate(ItemBase):
  """Schema for updating an existing item

  Args:
      ItemBase (_type_): _description_
  """
  title: Optional[str] = Field(None, min_length=1, max_length=255)
  description: Optional[str] = Field(None, max_length=1000)
  price: Optional[float] = Field(None, ge=0)
  is_available: Optional[bool] = None

class ItemWithOwner(Item):
  """Schema for a single item with owner

  Args:
      Item (_type_): _description_
  """
  owner: "UserInItem"

class UserInItem(BaseSchema):
  """Schema for a user in an item

  Args:
      BaseSchema (_type_): _description_
  """
  id: int
  username: str
  email: str
  full_name: Optional[str] = None