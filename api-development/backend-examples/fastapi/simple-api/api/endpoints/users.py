from typing import List
from fastapi import APIRouter, HTTPException, status
from app.schemas.user import User, UserCreate, UserUpdate

router = APIRouter()

# In-memory storage for demo (replace with actual database)
users_db = {}
user_id_counter = 1


@router.post("/", response_model=User, status_code=status.HTTP_201_CREATED)
async def create_user(user: UserCreate):
    """
    Create a new user
    """
    global user_id_counter
    
    # Check if user already exists
    for existing_user in users_db.values():
        if existing_user["email"] == user.email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )
        if existing_user["username"] == user.username:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already taken"
            )
    
    from datetime import datetime
    user_dict = user.model_dump(exclude={"password"})
    user_dict.update({
        "id": user_id_counter,
        "hashed_password": f"hashed_{user.password}",  # Replace with actual hashing
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    })
    
    users_db[user_id_counter] = user_dict
    user_id_counter += 1
    
    return user_dict


@router.get("/", response_model=List[User])
async def get_users(skip: int = 0, limit: int = 100):
    """
    Retrieve all users
    """
    all_users = list(users_db.values())
    return all_users[skip:skip + limit]


@router.get("/{user_id}", response_model=User)
async def get_user(user_id: int):
    """
    Get user by ID
    """
    if user_id not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    return users_db[user_id]


@router.put("/{user_id}", response_model=User)
async def update_user(user_id: int, user_update: UserUpdate):
    """
    Update user
    """
    if user_id not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    from datetime import datetime
    stored_user = users_db[user_id]
    update_data = user_update.model_dump(exclude_unset=True)
    
    if "password" in update_data:
        update_data["hashed_password"] = f"hashed_{update_data.pop('password')}"
    
    update_data["updated_at"] = datetime.utcnow()
    stored_user.update(update_data)
    
    return stored_user


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(user_id: int):
    """
    Delete user
    """
    if user_id not in users_db:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    del users_db[user_id]