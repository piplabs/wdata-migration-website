import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { MigrationCard } from "@/components/MigrationCard";
import { PromoCard } from "@/components/PromoCard";

export default function Home() {
  return (
    <div className="flex min-h-dvh flex-col">
      <Header />
      <main className="flex flex-1 items-center justify-center px-4 py-12">
        <MigrationCard />
      </main>
      <Footer />
      <PromoCard />
    </div>
  );
}
