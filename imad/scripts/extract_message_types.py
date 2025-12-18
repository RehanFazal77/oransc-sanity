import requests
import json
import base64
import re
from typing import Dict, List, Optional, Tuple
import time

class RicAppMessageExtractor:
    def __init__(self, github_token: Optional[str] = None):
        """
        Initialize the extractor with optional GitHub token for higher rate limits.
        
        Args:
            github_token: GitHub personal access token
        """
        self.github_token = github_token
        self.headers = {}
        if github_token:
            self.headers['Authorization'] = f'token {github_token}'
        self.headers['Accept'] = 'application/vnd.github.v3+json'
        self.base_url = 'https://api.github.com'
        self.results = {}
    
    def find_ric_app_repos(self) -> List[str]:
        """Find all repositories matching 'ric-app' in o-ran-sc organization."""
        print("🔍 Searching for ric-app repositories in o-ran-sc...")
        repos = []
        page = 1
        
        while True:
            url = f"{self.base_url}/orgs/o-ran-sc/repos"
            params = {'page': page, 'per_page': 100}
            
            try:
                response = requests.get(url, headers=self.headers, params=params, timeout=10)
                response.raise_for_status()
                data = response.json()
                
                if not data:
                    break
                
                for repo in data:
                    if 'ric-app' in repo['name']:
                        repos.append(repo['name'])
                        print(f"  ✓ Found: {repo['name']}")
                
                page += 1
            except requests.exceptions.RequestException as e:
                print(f"❌ Error fetching repos: {e}")
                break
        
        print(f"\n📊 Total ric-app repos found: {len(repos)}\n")
        return repos
    
    def search_messages_in_repo(self, repo_name: str) -> List[Tuple[str, str]]:
        """Search for rxMessages and txMessages patterns in all files of a repo."""
        print(f"📦 Processing: {repo_name}")
        matches = []
        
        try:
            # Use GitHub's search API to find files containing "rxMessages"
            search_url = f"{self.base_url}/search/code"
            params = {
                'q': f'rxMessages repo:o-ran-sc/{repo_name}',
                'per_page': 100
            }
            
            print(f"  🔎 Searching for rxMessages...")
            response = requests.get(search_url, headers=self.headers, params=params, timeout=10)
            
            # Handle 401/403 by falling back to tree search
            if response.status_code in [401, 403, 422]:
                print(f"  ⚠️  Search API limited, trying tree traversal...")
                matches = self._search_in_tree(repo_name)
            else:
                response.raise_for_status()
                data = response.json()
                
                if 'items' in data and data['items']:
                    print(f"  ✓ Found {len(data['items'])} file(s) with rxMessages")
                    for item in data['items']:
                        file_path = item['path']
                        print(f"    📄 {file_path}")
                        content = self._get_file_content(repo_name, file_path)
                        if content:
                            rx_msgs, tx_msgs = self._extract_messages(content)
                            if rx_msgs or tx_msgs:
                                matches.append((file_path, content, rx_msgs, tx_msgs))
                else:
                    print(f"  ℹ️  No files found with rxMessages, trying tree search...")
                    matches = self._search_in_tree(repo_name)
        
        except requests.exceptions.RequestException as e:
            print(f"  ⚠️  Search error: {e}, trying tree search...")
            matches = self._search_in_tree(repo_name)
        
        return matches
    
    def _search_in_tree(self, repo_name: str, path: str = '', depth: int = 0, max_depth: int = 8) -> List[Tuple[str, str]]:
        """Fallback: traverse repo tree and search files for messages."""
        matches = []
        
        if depth > max_depth:
            return matches
        
        try:
            url = f"{self.base_url}/repos/o-ran-sc/{repo_name}/contents/{path}"
            response = requests.get(url, headers=self.headers, timeout=10)
            
            if response.status_code == 404:
                return matches
            
            response.raise_for_status()
            data = response.json()
            
            if not isinstance(data, list):
                data = [data]
            
            for item in data:
                if item.get('type') == 'file':
                    # Check if file is likely to contain config (json, yaml, py, js, etc)
                    name = item.get('name', '')
                    if any(name.endswith(ext) for ext in ['.json', '.yaml', '.yml', '.py', '.js', '.go', '.ts', '.xml']):
                        file_path = item.get('path', '')
                        content = self._get_file_content(repo_name, file_path)
                        if content:
                            rx_msgs, tx_msgs = self._extract_messages(content)
                            if rx_msgs or tx_msgs:
                                matches.append((file_path, content, rx_msgs, tx_msgs))
                
                elif item.get('type') == 'dir':
                    item_path = item.get('path', '')
                    matches.extend(self._search_in_tree(repo_name, item_path, depth + 1, max_depth))
                    time.sleep(0.05)
        
        except Exception as e:
            pass
        
        return matches
    
    def _get_file_content(self, repo_name: str, file_path: str) -> Optional[str]:
        """Fetch file content from GitHub."""
        try:
            url = f"{self.base_url}/repos/o-ran-sc/{repo_name}/contents/{file_path}"
            response = requests.get(url, headers=self.headers, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if 'content' in data:
                content = base64.b64decode(data['content']).decode('utf-8', errors='ignore')
                return content
        except Exception as e:
            pass
        
        return None
    
    def _extract_messages(self, content: str) -> Tuple[List[str], List[str]]:
        """Extract rxMessages and txMessages from file content."""
        rx_messages = []
        tx_messages = []
        
        # Pattern to match "rxMessages": [...] or "rxMessages" : [...]
        rx_pattern = r'"rxMessages"\s*:\s*\[(.*?)\]'
        tx_pattern = r'"txMessages"\s*:\s*\[(.*?)\]'
        
        # Find all matches
        rx_matches = re.findall(rx_pattern, content, re.DOTALL)
        tx_matches = re.findall(tx_pattern, content, re.DOTALL)
        
        # Extract message names from matches
        for match in rx_matches:
            messages = re.findall(r'"([^"]+)"', match)
            if messages:
                rx_messages.extend(messages)
        
        for match in tx_matches:
            messages = re.findall(r'"([^"]+)"', match)
            if messages:
                tx_messages.extend(messages)
        
        return rx_messages, tx_messages
    
    def process_all_repos(self) -> Dict:
        """Process all ric-app repos and extract messages."""
        repos = self.find_ric_app_repos()
        
        for repo_name in repos:
            matches = self.search_messages_in_repo(repo_name)
            
            if matches:
                repo_data = {}
                for file_path, content, rx_msgs, tx_msgs in matches:
                    repo_data[file_path] = {
                        'rxMessages': rx_msgs,
                        'txMessages': tx_msgs
                    }
                    print(f"      ✓ rxMessages: {rx_msgs}")
                    print(f"      ✓ txMessages: {tx_msgs}")
                
                self.results[repo_name] = repo_data
            else:
                print(f"  ℹ️  No rxMessages/txMessages found in {repo_name}\n")
        
        return self.results
    
    def print_summary(self):
        """Print a summary of all findings."""
        print("\n" + "="*80)
        print("📋 SUMMARY - rxMessages and txMessages from ric-app Repos")
        print("="*80 + "\n")
        
        if not self.results:
            print("❌ No results found.")
            return
        
        total_repos_with_messages = len(self.results)
        print(f"✓ Found messages in {total_repos_with_messages} repo(s)\n")
        
        for repo_name, files in sorted(self.results.items()):
            print(f"📦 {repo_name}")
            for file_path, messages in files.items():
                print(f"  📄 {file_path}")
                print(f"    rxMessages: {messages['rxMessages']}")
                print(f"    txMessages: {messages['txMessages']}")
            print()
    
    def save_to_file(self, filename: str = 'ric_app_messages.json'):
        """Save results to a JSON file."""
        try:
            with open(filename, 'w') as f:
                json.dump(self.results, f, indent=2)
            print(f"✅ Results saved to {filename}")
        except IOError as e:
            print(f"❌ Error saving to file: {e}")

# Main execution
if __name__ == '__main__':
    
    print("Starting RIC-APP Message Extractor...\n")
    extractor = RicAppMessageExtractor(github_token=GITHUB_TOKEN)
    results = extractor.process_all_repos()
    extractor.print_summary()
    extractor.save_to_file('ric_app_messages.json')
    
    print("\n✨ Done!")