<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Tag;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Tags livres nas transações (ex.: "iFood", "Amazon").
 */
class TagTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->account = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Alimentação')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function store(array $overrides = []): Transaction
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Pedido',
                'amount' => 50,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                'tags' => ['iFood'],
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();

        return Transaction::query()->latest('created_at')->firstOrFail();
    }

    /** @return list<string> */
    private function tagNames(Transaction $transaction): array
    {
        return $transaction->tags()->orderBy('name')->pluck('name')->all();
    }

    public function test_tags_are_created_without_duplicates(): void
    {
        $transaction = $this->store(['tags' => ['iFood', 'ifood', ' Amazon ']]);

        $this->assertSame(['Amazon', 'iFood'], $this->tagNames($transaction));
        $this->assertSame(2, Tag::where('user_id', $this->user->id)->count());
    }

    public function test_a_different_spelling_reuses_the_existing_tag(): void
    {
        $this->store(['tags' => ['iFood']]);
        $second = $this->store(['tags' => ['IFOOD']]);

        $this->assertSame(1, Tag::where('user_id', $this->user->id)->count());
        $this->assertSame(['iFood'], $this->tagNames($second));
    }

    public function test_every_parcel_gets_the_tags(): void
    {
        $this->store(['description' => 'Celular', 'is_installment' => true, 'installments_count' => 3, 'tags' => ['Amazon']]);

        $parcels = Transaction::whereNotNull('installment_id')->get();
        $this->assertCount(3, $parcels);
        $parcels->each(fn (Transaction $p) => $this->assertSame(['Amazon'], $this->tagNames($p)));
    }

    public function test_next_recurring_occurrence_copies_the_tags(): void
    {
        $this->store(['description' => 'Spotify', 'is_recurring' => true, 'tags' => ['Assinaturas']]);

        $this->travelTo('2026-12-18 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $occurrences = Transaction::whereNotNull('recurring_id')->orderBy('date')->get();
        $this->assertCount(2, $occurrences);
        $this->assertSame(['Assinaturas'], $this->tagNames($occurrences[1]));
    }

    public function test_editing_replaces_the_tags_and_omitting_them_keeps_them(): void
    {
        $transaction = $this->store(['tags' => ['iFood']]);

        $payload = [
            'description' => 'Pedido',
            'amount' => 50,
            'type' => 'expense',
            'category_id' => $this->category->id,
            'account_id' => $this->account->id,
            'date' => '2026-11-18',
        ];

        $this->actingAs($this->user)->put(route('transactions.update', $transaction), [...$payload, 'tags' => ['Rappi']])
            ->assertSessionHasNoErrors();
        $this->assertSame(['Rappi'], $this->tagNames($transaction));

        $this->actingAs($this->user)->put(route('transactions.update', $transaction), $payload)
            ->assertSessionHasNoErrors();
        $this->assertSame(['Rappi'], $this->tagNames($transaction));
    }

    public function test_list_can_be_filtered_by_tag(): void
    {
        $this->store(['description' => 'Pedido 1', 'tags' => ['iFood']]);
        $this->store(['description' => 'Pedido 2', 'tags' => ['iFood']]);
        $this->store(['description' => 'Livro', 'tags' => ['Amazon']]);

        $ifood = Tag::where('name', 'iFood')->firstOrFail();

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['tag_id' => $ifood->id]))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 2)
                ->where('summary.expense', fn ($v) => (float) $v === 100.0));
    }

    public function test_renaming_to_an_existing_name_merges_the_tags(): void
    {
        $a = $this->store(['tags' => ['Ifood']]);
        $b = $this->store(['tags' => ['Delivery']]);

        $delivery = Tag::where('name', 'Delivery')->firstOrFail();

        $this->actingAs($this->user)->put(route('tags.update', $delivery), ['name' => 'IFOOD'])
            ->assertSessionHasNoErrors();

        $this->assertSame(1, Tag::where('user_id', $this->user->id)->count());
        $this->assertSame(['IFOOD'], $this->tagNames($a));
        $this->assertSame(['IFOOD'], $this->tagNames($b));
    }

    public function test_deleting_a_tag_keeps_the_transactions(): void
    {
        $transaction = $this->store(['tags' => ['iFood']]);
        $tag = Tag::firstOrFail();

        $this->actingAs($this->user)->delete(route('tags.destroy', $tag))->assertSessionHasNoErrors();

        $this->assertNotNull($transaction->fresh());
        $this->assertSame([], $this->tagNames($transaction));
    }

    public function test_tags_are_personal(): void
    {
        $this->store(['tags' => ['iFood']]);
        $tag = Tag::firstOrFail();

        $this->actingAs(User::factory()->create())
            ->put(route('tags.update', $tag), ['name' => 'X'])
            ->assertNotFound();
    }
}
