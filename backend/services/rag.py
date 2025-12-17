from langchain_ollama import ChatOllama, OllamaEmbeddings
from langchain_chroma import Chroma
from langchain_core.tools import create_retriever_tool

from services.ingest import DB_PATH

class RAG:
    def __init__(self):
        self.vectorstore = Chroma(
            persist_directory=DB_PATH,
            embedding_function=OllamaEmbeddings(model="nomic-embed-text")
        )
        
        self.retriever = self.vectorstore.as_retriever(search_kwargs={"k": 5})

    def search_knowledge_base(self, query):
        docs = self.retriever.invoke(query)
        
        formatted_results = "\n\n".join(
            [f"--- Document Source: {doc.metadata.get('source', 'Unknown')} ---\n{doc.page_content}" for doc in docs]
        )
        
        return formatted_results if formatted_results else "No relevant documents found."

rag = RAG()