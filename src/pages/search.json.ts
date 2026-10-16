// src/pages/search.json.ts
export async function GET() {
  const postFiles = import.meta.glob('./blog/**/*.{md,mdx}', { eager: true });
  const posts = Object.values(postFiles);

  const searchData = posts.map((post: any) => {
    // Safely extract text content whether it's .md or .mdx
    let rawText = '';
    
    if (typeof post.compiledContent === 'function') {
      rawText = post.compiledContent();
    } else if (typeof post.rawContent === 'function') {
      rawText = post.rawContent();
    }

    // Ensure it's a string before calling .replace()
    const plainTextContent = typeof rawText === 'string' 
      ? rawText.replace(/<[^>]*>/g, ' ') 
      : '';

    return {
      title: post.frontmatter?.title || '',
      description: post.frontmatter?.description || '',
      url: post.url || '',
      date: post.frontmatter?.date || '',
      category: post.frontmatter?.category || '',
      tags: post.frontmatter?.tags || [],
      content: plainTextContent
    };
  });

  return new Response(JSON.stringify(searchData), {
    headers: { 'Content-Type': 'application/json' }
  });
}