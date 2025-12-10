
class Memory:
    def __init__(self):
        self.conversation_history = []
        self.page_content = None
        self.url = None

    def set_page_info(self, page_content, url):
        self.page_content = page_content
        self.url = url

    def get_page_info(self):
        return self.page_content, self.url

    def add_message(self, message):
        self.conversation_history.append(message)

    def get_history(self):
        return self.conversation_history

memory = Memory()