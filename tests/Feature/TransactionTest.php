<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TransactionTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->account = app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Alimentação')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function payload(array $overrides = []): array
    {
        return [
            'description' => 'Mercado',
            'amount' => 150.50,
            'type' => 'expense',
            'category_id' => $this->category->id,
            'account_id' => $this->account->id,
            'date' => now()->toDateString(),
            'is_installment' => false,
            'installments_count' => 2,
            'is_recurring' => false,
            'frequency' => 'monthly',
            ...$overrides,
        ];
    }

    public function test_single_expense_updates_account_balance(): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload())
            ->assertSessionHasNoErrors()
            ->assertRedirect();

        $this->assertSame(1, Transaction::count());
        $this->assertEquals(-150.50, (float) $this->account->fresh()->balance);
    }

    public function test_installments_are_split_and_sum_to_total(): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload([
                'amount' => 100,
                'is_installment' => true,
                'installments_count' => 3,
            ]))
            ->assertSessionHasNoErrors();

        $transactions = Transaction::orderBy('installment_number')->get();

        $this->assertCount(3, $transactions);
        $this->assertEquals(100.0, round($transactions->sum(fn ($t) => (float) $t->amount), 2));
        $this->assertSame([1, 2, 3], $transactions->pluck('installment_number')->all());
        // Só a primeira parcela afeta o saldo na criação.
        $this->assertEquals(-33.33, (float) $this->account->fresh()->balance);
    }

    public function test_recurring_transaction_creates_first_occurrence(): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload([
                'is_recurring' => true,
                'frequency' => 'weekly',
            ]))
            ->assertSessionHasNoErrors();

        $transaction = Transaction::firstOrFail();

        $this->assertNotNull($transaction->recurring_id);
        $this->assertDatabaseHas('recurring_transactions', [
            'frequency' => 'weekly',
            'next_run' => now()->addWeek()->toDateString(),
        ]);
    }

    public function test_cannot_use_another_users_account(): void
    {
        $other = User::factory()->create();
        $otherAccount = app(IAccountService::class)->createDefaultForUser($other->id);

        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload(['account_id' => $otherAccount->id]))
            ->assertSessionHasErrors('account_id');

        $this->assertSame(0, Transaction::count());
    }

    public function test_user_can_create_account_and_category(): void
    {
        $this->actingAs($this->user)
            ->post(route('accounts.store'), ['name' => 'Nubank', 'type' => 'checking'])
            ->assertSessionHasNoErrors();

        $this->actingAs($this->user)
            ->post(route('categories.store'), [
                'name' => 'Mercado',
                'type' => 'expense',
                'color' => 'emerald',
                'icon' => 'shopping-bag',
            ])
            ->assertSessionHasNoErrors();

        $this->assertDatabaseHas('accounts', ['user_id' => $this->user->id, 'name' => 'Nubank']);
        $this->assertDatabaseHas('categories', ['user_id' => $this->user->id, 'name' => 'Mercado', 'color' => 'emerald']);
    }

    public function test_category_name_must_be_unique_per_user(): void
    {
        $this->actingAs($this->user)
            ->post(route('categories.store'), [
                'name' => 'Alimentação',
                'type' => 'expense',
                'color' => 'orange',
                'icon' => 'utensils',
            ])
            ->assertSessionHasErrors('name');
    }
}
