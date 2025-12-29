
from pydantic import BaseModel, Field
from typing import List

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
