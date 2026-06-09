import os
import ray
from langchain_anthropic import ChatAnthropic
from langchain.agents import create_tool_calling_agent, AgentExecutor
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.tools import tool


@tool
def add_numbers(a: float, b: float) -> float:
    """Add two numbers together."""
    return a + b


@tool
def multiply_numbers(a: float, b: float) -> float:
    """Multiply two numbers together."""
    return a * b


@tool
def classify_industry(company_name: str) -> str:
    """Classify a company into one of: Technology, Healthcare, Finance, Retail, Manufacturing, Consulting, Law Firm, Real Estate, Other."""
    lookup = {
        "apple": "Technology", "google": "Technology", "microsoft": "Technology",
        "amazon": "Technology", "meta": "Technology", "nvidia": "Technology",
        "pfizer": "Healthcare", "johnson": "Healthcare", "unitedhealth": "Healthcare",
        "jpmorgan": "Finance", "goldman": "Finance", "berkshire": "Finance",
        "walmart": "Retail", "target": "Retail", "costco": "Retail",
        "boeing": "Manufacturing", "ford": "Manufacturing", "caterpillar": "Manufacturing",
        "mckinsey": "Consulting", "deloitte": "Consulting", "accenture": "Consulting",
    }
    name_lower = company_name.lower()
    for key, industry in lookup.items():
        if key in name_lower:
            return f"{company_name} → {industry}"
    return f"{company_name} → Other"


def make_agent():
    llm = ChatAnthropic(model="claude-haiku-4-5-20251001", temperature=0)
    tools = [add_numbers, multiply_numbers, classify_industry]
    prompt = ChatPromptTemplate.from_messages([
        ("system", "You are a helpful assistant. Use the available tools to answer questions accurately."),
        ("human", "{input}"),
        MessagesPlaceholder(variable_name="agent_scratchpad"),
    ])
    agent = create_tool_calling_agent(llm, tools, prompt)
    return AgentExecutor(agent=agent, tools=tools, verbose=True)


@ray.remote
def run_agent(question: str) -> dict:
    executor = make_agent()
    result = executor.invoke({"input": question})
    return {"question": question, "answer": result["output"]}


if __name__ == "__main__":
    ray.init()

    questions = [
        "What industry is Microsoft in?",
        "What is 2847 multiplied by 3921?",
        "What industry is Goldman Sachs in? Also, what is 365 times 24?",
    ]

    print(f"Running {len(questions)} agent questions in parallel on Ray...\n")
    futures = [run_agent.remote(q) for q in questions]
    results = ray.get(futures)

    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    for r in results:
        print(f"\nQ: {r['question']}")
        print(f"A: {r['answer']}")
