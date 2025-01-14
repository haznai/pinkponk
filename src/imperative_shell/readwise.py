import httpx
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class ReadwiseItem:
    id: str
    url: str
    title: str | None


async def get_list_of_all_articles(READWISE_API_KEY: str) -> list[ReadwiseItem] | None:
    results: list[ReadwiseItem] = []
    parsed_all_results = False
    next_page_cursor = None
    async with httpx.AsyncClient() as client:
        while not parsed_all_results:
            response = await client.get(
                url="https://readwise.io/api/v3/list/",
                headers={"Authorization": f"Token {READWISE_API_KEY}"},
                # page_cursor is for pagination
                params={"pageCursor": next_page_cursor}
                if next_page_cursor is not None
                else None,
            )

            if response.is_error:
                return None

            json_response = response.json()

            if "results" not in json_response:
                return None

            # pagination handling
            if "nextPageCursor" in json_response:
                next_page_cursor = json_response["nextPageCursor"]
                if next_page_cursor is None or next_page_cursor == "":
                    parsed_all_results = True

            parsed_items = [
                ReadwiseItem(item["id"], item["url"], item.get("title", None))
                for item in json_response["results"]
            ]

            if parsed_items is None:
                return None

            results.extend(parsed_items)

    return results
