import { DocsPage, DocsBody } from "fumadocs-ui/page";
import { notFound } from "next/navigation";
import { source } from "@/lib/source";

export default function Page({ params }: { params: { slug?: string[] } }) {
  const page = source.getPage(params.slug);
  if (!page) notFound();

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <h1>{page.data.title}</h1>
      <DocsBody>
        <page.data.body />
      </DocsBody>
    </DocsPage>
  );
}

export function generateStaticParams() {
  return source.generateParams();
}

export function generateMetadata({ params }: { params: { slug?: string[] } }) {
  const page = source.getPage(params.slug);
  if (!page) return {};

  return {
    title: page.data.title,
    description: page.data.description
  };
}
