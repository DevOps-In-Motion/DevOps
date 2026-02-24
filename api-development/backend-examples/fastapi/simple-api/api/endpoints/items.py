from typing import List
from fastapi import APIRouter, HTTPException, status
from app.schemas.item import Item, ItemCreate, ItemUpdate

router = APIRouter()

# In-memory storage for demo
items_db = {}
item_id_counter = 1


@router.post("/", response_model=Item, status_code=status.HTTP_201_CREATED)
async def create_item(item: ItemCreate, owner_id: int = 1):
    """
    Create a new item
    """
    global item_id_counter
    
    from datetime import datetime
    item_dict = item.model_dump()
    item_dict.update({
        "id": item_id_counter,
        "owner_id": owner_id,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    })
    
    items_db[item_id_counter] = item_dict
    item_id_counter += 1
    
    return item_dict


@router.get("/", response_model=List[Item])
async def get_items(skip: int = 0, limit: int = 100):
    """
    Retrieve all items
    """
    all_items = list(items_db.values())
    return all_items[skip:skip + limit]


@router.get("/{item_id}", response_model=Item)
async def get_item(item_id: int):
    """
    Get item by ID
    """
    if item_id not in items_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Item not found"
        )
    return items_db[item_id]


@router.put("/{item_id}", response_model=Item)
async def update_item(item_id: int, item_update: ItemUpdate):
    """
    Update item
    """
    if item_id not in items_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Item not found"
        )
    
    from datetime import datetime
    stored_item = items_db[item_id]
    update_data = item_update.model_dump(exclude_unset=True)
    update_data["updated_at"] = datetime.utcnow()
    stored_item.update(update_data)
    
    return stored_item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: int):
    """
    Delete item
    """
    if item_id not in items_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Item not found"
        )
    del items_db[item_id]