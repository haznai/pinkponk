import pytest
from os import getenv

from src.imperative_shell import readwise


@pytest.mark.asyncio
async def test_readwise():
    api_key = getenv("READWISE_API_KEY")
    assert api_key is not None
    articles = await readwise.get_list_of_all_articles(api_key) is not None
    assert articles is not None
