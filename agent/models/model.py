
from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum

class SheetAction(str, Enum):
    READ = "read"
    APPEND = "append"
    UPDATE = "update"
    CREATE = "create"
    CLEAR = "clear"
class JobApplicationSchema(BaseModel):
    company: str
    position: str
    url: str

class WebSearchSchema(BaseModel):
    query: str

class ListDirectorySchema(BaseModel):
    path: str = Field(description="The absolute path of the directory to list.")

class ReadFileSchema(BaseModel):
    path: str = Field(description="The absolute path of the file to read.")

class CollectFilesSchema(BaseModel):
    path: str = Field(description="The absolute path of the directory or file to collect paths from.")

class SeparateFilesSchema(BaseModel):
    file_paths: List[str]

class OpenApplicationSchema(BaseModel):
    app_name: str

class KBSearchSchema(BaseModel):
    query: str

class SheetToolInput(BaseModel):
    action: SheetAction = Field(
        ..., 
        description="The operation to perform. Options: 'read', 'append', 'update', 'create', 'clear'."
    )
    spreadsheet_id: Optional[str] = Field(
        None, 
        description="The ID of the spreadsheet. If creating a new sheet, leave this blank."
    )
    range_name: str = Field(
        ..., 
        description="The A1 notation range (e.g., 'Sheet1!A1:B5'). For 'create', use this as the title."
    )
    values_json: Optional[str] = Field(
        None, 
        description="A JSON string representing the data rows. Example: '[[\"Name\", \"Age\"], [\"Alice\", \"30\"]]'. Required for append/update."
    )


# Schema for web socket responses
# CamelCase for consistency with frontend
class ToolCallSchema(BaseModel):
    toolName: str
    toolArgs: dict

class ToolResultSchema(BaseModel):
    toolName: str
    result: str

class ResponseContentSchema(BaseModel):
    text: str
    images: Optional[List[str]] = None

class ThoughtContentSchema(BaseModel):
    text: str