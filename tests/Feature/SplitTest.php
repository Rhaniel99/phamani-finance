<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Fase 3: contatos e divisão de contas.
 */
class SplitTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $checking;

    private Category $category;

    private Contact $mozi;

    private Contact $mae;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Transporte')->firstOrFail();

        $this->checking = Account::create([
            'user_id' => $this->user->id,
            'name' => 'Bradesco',
            'type' => 'checking',
            'balance' => 1000,
        ]);

        $this->actingAs($this->user)->post(route('contacts.store'), ['name' => 'Mozi'])->assertSessionHasNoErrors();
        $this->actingAs($this->user)->post(route('contacts.store'), ['name' => 'Mãe da Mozi'])->assertSessionHasNoErrors();

        $this->mozi = Contact::where('name', 'Mozi')->firstOrFail();
        $this->mae = Contact::where('name', 'Mãe da Mozi')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function payload(array $overrides = []): array
    {
        return [
            'description' => 'Uber',
            'amount' => 333.75,
            'type' => 'expense',
            'category_id' => $this->category->id,
            'account_id' => $this->checking->id,
            'date' => '2026-11-18',
            'is_installment' => false,
            'installments_count' => 2,
            'installment_start' => 1,
            'amount_mode' => 'total',
            'is_recurring' => false,
            'frequency' => 'monthly',
            'split' => [
                'mode' => 'equal',
                'participants' => [
                    ['contact_id' => null],
                    ['contact_id' => $this->mozi->id],
                    ['contact_id' => $this->mae->id],
                ],
                'paid_by_contact_id' => null,
            ],
            ...$overrides,
        ];
    }

    private function store(array $overrides = []): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload($overrides))
            ->assertSessionHasNoErrors();
    }

    /**
     * @return array<string, float>
     */
    private function shares(Transaction $transaction): array
    {
        return TransactionSplit::where('transaction_id', $transaction->id)->get()
            ->mapWithKeys(fn ($s) => [$s->contact_id ?? 'me' => (float) $s->amount])
            ->all();
    }

    public function test_equal_split_paid_by_me(): void
    {
        $this->store();

        $t = Transaction::firstOrFail();

        $this->assertEquals(111.25, (float) $t->amount);
        $this->assertEquals(333.75, (float) $t->total_amount);
        $this->assertEquals(['me' => 111.25, $this->mozi->id => 111.25, $this->mae->id => 111.25], $this->shares($t));
        // Sai o total da sua conta…
        $this->assertEquals(666.25, (float) $this->checking->fresh()->balance);

        // …mas a despesa do mês é só a sua parte.
        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page
                ->where('kpis.expense.value', 111.25)
                ->has('contacts', 2));
    }

    public function test_leftover_cent_goes_to_the_payer(): void
    {
        $this->store(['amount' => 100]);
        $this->assertEquals(['me' => 33.34, $this->mozi->id => 33.33, $this->mae->id => 33.33], $this->shares(Transaction::firstOrFail()));

        Transaction::query()->delete();

        $this->store(['amount' => 100, 'split' => [...$this->payload()['split'], 'paid_by_contact_id' => $this->mozi->id]]);
        $this->assertEquals(['me' => 33.33, $this->mozi->id => 33.34, $this->mae->id => 33.33], $this->shares(Transaction::firstOrFail()));
    }

    public function test_paid_by_someone_else_does_not_touch_my_accounts(): void
    {
        $payload = $this->payload(['split' => [...$this->payload()['split'], 'paid_by_contact_id' => $this->mozi->id]]);
        unset($payload['account_id']);

        $this->actingAs($this->user)
            ->post(route('transactions.store'), $payload)
            ->assertSessionHasNoErrors();

        $t = Transaction::firstOrFail();

        $this->assertNull($t->account_id);
        $this->assertSame($this->mozi->id, $t->paid_by_contact_id);
        $this->assertEquals(111.25, (float) $t->amount);
        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
    }

    public function test_account_is_required_when_i_paid(): void
    {
        $payload = $this->payload();
        unset($payload['account_id']);

        $this->actingAs($this->user)
            ->post(route('transactions.store'), $payload)
            ->assertSessionHasErrors('account_id');
    }

    public function test_custom_split_must_add_up(): void
    {
        $custom = fn (float $me, float $mozi) => [
            'mode' => 'custom',
            'participants' => [
                ['contact_id' => null, 'amount' => $me],
                ['contact_id' => $this->mozi->id, 'amount' => $mozi],
            ],
            'paid_by_contact_id' => null,
        ];

        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload(['amount' => 179.08, 'split' => $custom(89.54, 80)]))
            ->assertSessionHasErrors('split.participants');

        $this->store(['amount' => 179.08, 'split' => $custom(100, 79.08)]);

        $t = Transaction::firstOrFail();
        $this->assertEquals(100.0, (float) $t->amount);
        $this->assertEquals(['me' => 100.0, $this->mozi->id => 79.08], $this->shares($t));
    }

    public function test_only_expenses_can_be_split_and_payer_must_participate(): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload(['type' => 'income', 'category_id' => Category::where('user_id', $this->user->id)->where('name', 'Salário')->value('id')]))
            ->assertSessionHasErrors('split');

        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload(['split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $this->mozi->id]],
                'paid_by_contact_id' => $this->mae->id,
            ]]))
            ->assertSessionHasErrors('split.paid_by_contact_id');

        $this->assertSame(0, Transaction::count());
    }

    public function test_cannot_split_with_another_users_contact(): void
    {
        $other = User::factory()->create();
        $stranger = Contact::create(['user_id' => $other->id, 'name' => 'Estranho']);

        $this->actingAs($this->user)
            ->post(route('transactions.store'), $this->payload(['split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $stranger->id]],
                'paid_by_contact_id' => null,
            ]]))
            ->assertSessionHasErrors();

        $this->assertSame(0, Transaction::count());
    }

    public function test_split_card_purchase_puts_full_amount_on_invoice(): void
    {
        $card = Account::create([
            'user_id' => $this->user->id,
            'name' => 'Nubank',
            'type' => 'credit',
            'balance' => 0,
            'credit_limit' => 5000,
            'closing_day' => 25,
            'due_day' => 5,
        ]);

        $this->store(['account_id' => $card->id]);

        $summary = app(ICreditCardService::class)->summary($card->fresh());
        $this->assertEquals(333.75, $summary['used']);
        $this->assertEquals(111.25, (float) Transaction::firstOrFail()->amount);
    }

    public function test_installment_split_divides_each_parcel(): void
    {
        $this->store([
            'amount' => 300,
            'is_installment' => true,
            'installments_count' => 3,
            'split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $this->mozi->id]],
                'paid_by_contact_id' => null,
            ],
        ]);

        $parcels = Transaction::orderBy('installment_number')->get();

        $this->assertCount(3, $parcels);
        $this->assertTrue($parcels->every(fn ($p) => (float) $p->amount === 50.0 && (float) $p->total_amount === 100.0));
        $this->assertEquals(900.0, (float) $this->checking->fresh()->balance); // só a 1ª parcela (hoje), valor cheio
    }

    public function test_recurring_split_copies_division_and_payer(): void
    {
        $payload = $this->payload([
            'is_recurring' => true,
            'split' => [...$this->payload()['split'], 'paid_by_contact_id' => $this->mozi->id],
        ]);
        unset($payload['account_id']);

        $this->actingAs($this->user)->post(route('transactions.store'), $payload)->assertSessionHasNoErrors();

        $this->travelTo('2026-12-18 01:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $next = Transaction::orderByDesc('date')->firstOrFail();

        $this->assertSame('2026-12-18', $next->date->toDateString());
        $this->assertNull($next->account_id);
        $this->assertSame($this->mozi->id, $next->paid_by_contact_id);
        $this->assertEquals(111.25, (float) $next->amount);
        $this->assertCount(3, $this->shares($next));
        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
    }

    public function test_changing_payer_to_someone_else_reverts_my_balance(): void
    {
        $this->store();
        $t = Transaction::firstOrFail();
        $this->assertEquals(666.25, (float) $this->checking->fresh()->balance);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $t), [
                'description' => 'Uber',
                'amount' => 333.75,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'date' => '2026-11-18',
                'split' => [...$this->payload()['split'], 'paid_by_contact_id' => $this->mozi->id],
            ])
            ->assertSessionHasNoErrors();

        $this->assertEquals(1000.0, (float) $this->checking->fresh()->balance);
        $this->assertNull($t->fresh()->account_id);
    }

    public function test_removing_the_split_restores_full_amount(): void
    {
        $this->store();
        $t = Transaction::firstOrFail();

        $this->actingAs($this->user)
            ->put(route('transactions.update', $t), [
                'description' => 'Uber',
                'amount' => 333.75,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->checking->id,
                'date' => '2026-11-18',
                'split' => null,
            ])
            ->assertSessionHasNoErrors();

        $t->refresh();
        $this->assertEquals(333.75, (float) $t->amount);
        $this->assertNull($t->total_amount);
        $this->assertSame(0, TransactionSplit::count());
        $this->assertEquals(666.25, (float) $this->checking->fresh()->balance);
    }

    public function test_contact_names_are_unique_and_used_contacts_cannot_be_deleted(): void
    {
        $this->actingAs($this->user)
            ->post(route('contacts.store'), ['name' => 'Mozi'])
            ->assertSessionHasErrors('name');

        $this->store();

        $this->actingAs($this->user)->delete(route('contacts.destroy', $this->mozi));
        $this->assertNotNull($this->mozi->fresh());

        $unused = Contact::create(['user_id' => $this->user->id, 'name' => 'Fulano']);
        $this->actingAs($this->user)->delete(route('contacts.destroy', $unused));
        $this->assertNull($unused->fresh());
    }
}
