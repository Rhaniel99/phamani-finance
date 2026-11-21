<?php

namespace App\Services;

use App\Interfaces\Services\ITagService;
use App\Models\Tag;
use App\Models\Transaction;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class TagService implements ITagService
{
    public function listForUser(string $userId): Collection
    {
        return Tag::query()
            ->where('user_id', $userId)
            ->withCount('transactions')
            ->orderBy('name')
            ->get(['id', 'name']);
    }

    public function syncFor(iterable $transactions, string $userId, array $names): void
    {
        $ids = $this->resolve($userId, $names);

        foreach ($transactions as $transaction) {
            $transaction->tags()->sync($ids);
        }
    }

    public function copy(Transaction $from, Transaction $to): void
    {
        $to->tags()->sync($from->tags()->pluck('tags.id')->all());
    }

    public function rename(Tag $tag, string $name): Tag
    {
        $name = $this->clean($name);
        $slug = $this->slug($name);

        $existing = Tag::query()
            ->where('user_id', $tag->user_id)
            ->where('slug', $slug)
            ->whereKeyNot($tag->id)
            ->first();

        if ($existing === null) {
            $tag->update(['name' => $name, 'slug' => $slug]);

            return $tag;
        }

        // Mesmo nome de outra tag: junta as duas (as transações passam para a existente).
        return DB::transaction(function () use ($tag, $existing, $name) {
            $transactionIds = DB::table('transaction_tags')->where('tag_id', $tag->id)->pluck('transaction_id');

            DB::table('transaction_tags')->insertOrIgnore(
                $transactionIds->map(fn ($id) => ['transaction_id' => $id, 'tag_id' => $existing->id])->all(),
            );

            $tag->delete();
            $existing->update(['name' => $name]);

            return $existing;
        });
    }

    public function delete(Tag $tag): void
    {
        $tag->delete();
    }

    public function slug(string $name): string
    {
        return Str::of($name)->ascii()->lower()->squish()->value();
    }

    /**
     * Ids das tags com esses nomes (cria as novas). Repetidas e vazias são ignoradas.
     *
     * @param  list<string>  $names
     * @return list<string>
     */
    private function resolve(string $userId, array $names): array
    {
        $bySlug = [];
        foreach ($names as $name) {
            $name = $this->clean($name);
            $slug = $this->slug($name);
            if ($slug !== '' && ! isset($bySlug[$slug])) {
                $bySlug[$slug] = $name;
            }
        }

        $ids = [];
        foreach ($bySlug as $slug => $name) {
            $ids[] = Tag::query()->firstOrCreate(
                ['user_id' => $userId, 'slug' => $slug],
                ['name' => $name],
            )->id;
        }

        return $ids;
    }

    private function clean(string $name): string
    {
        return Str::of($name)->squish()->limit(40, '')->value();
    }
}
