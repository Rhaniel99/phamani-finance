<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\Share;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Status de pagamento: pago / pendente / atrasado, saldo só quando pago, débito automático
 * e "quem marca é quem pagou".
 */
class PaymentStatusTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create(['name' => 'Rhaniel']);
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->account = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Outros')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function store(array $overrides = [], ?User $as = null): void
    {
        $this->actingAs($as ?? $this->user)
            ->post(route('transactions.store'), [
                'description' => 'Boleto',
                'amount' => 100,
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
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();
    }

    private function balance(): float
    {
        return (float) $this->account->fresh()->balance;
    }

    public function test_initial_status_follows_the_date_and_cards_are_always_paid(): void
    {
        $this->store(['description' => 'Hoje']);
        $this->store(['description' => 'Futuro', 'date' => '2026-12-10']);

        $card = Account::create([
            'user_id' => $this->user->id, 'name' => 'Nubank', 'type' => 'credit', 'balance' => 0,
            'credit_limit' => 1000, 'closing_day' => 25, 'due_day' => 5,
        ]);
        $this->store(['description' => 'Cartão', 'account_id' => $card->id, 'date' => '2026-12-10']);

        $this->assertSame('2026-11-18', Transaction::where('name', 'Hoje')->firstOrFail()->paid_at->toDateString());
        $this->assertNull(Transaction::where('name', 'Futuro')->firstOrFail()->paid_at);
        $this->assertNotNull(Transaction::where('name', 'Cartão')->firstOrFail()->paid_at);
        $this->assertEquals(900.0, $this->balance()); // só "Hoje"
    }

    public function test_overdue_does_not_touch_balance_until_marked_paid(): void
    {
        $this->store(['date' => '2026-11-20']);
        $t = Transaction::firstOrFail();

        $this->travelTo('2026-11-25 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $this->assertNull($t->fresh()->paid_at);
        $this->assertEquals(1000.0, $this->balance());

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page->where('kpis.overdue.count', 1));

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'overdue']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 1)
                ->where('summary.overdue_count', 1));

        $this->actingAs($this->user)->post(route('transactions.pay', $t))->assertRedirect();
        $this->assertSame('2026-11-25', $t->fresh()->paid_at->toDateString());
        $this->assertEquals(900.0, $this->balance());

        $this->actingAs($this->user)->delete(route('transactions.unpay', $t))->assertRedirect();
        $this->assertNull($t->fresh()->paid_at);
        $this->assertEquals(1000.0, $this->balance());
    }

    public function test_recurring_without_auto_pay_waits_for_confirmation(): void
    {
        $this->store(['is_recurring' => true]);

        $this->travelTo('2026-12-18 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $next = Transaction::orderByDesc('date')->firstOrFail();
        $this->assertSame('2026-12-18', $next->date->toDateString());
        $this->assertNull($next->paid_at);
        $this->assertEquals(900.0, $this->balance()); // só a 1ª (hoje)
    }

    public function test_auto_pay_marks_due_parcels_as_paid(): void
    {
        $this->store(['is_installment' => true, 'installments_count' => 3, 'auto_pay' => true]);

        $this->travelTo('2026-12-18 01:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $parcels = Transaction::orderBy('installment_number')->get();
        $this->assertSame('2026-12-18', $parcels[1]->paid_at->toDateString());
        $this->assertNull($parcels[2]->paid_at);
        $this->assertEquals(800.0, $this->balance());
    }

    public function test_only_the_payer_marks_and_it_applies_to_everyone(): void
    {
        $mozi = User::factory()->create(['name' => 'Mozi']);
        app(IAccountService::class)->createDefaultForUser($mozi->id);
        app(ICategoryService::class)->createDefaultsForUser($mozi->id);
        $moziAccount = Account::create(['user_id' => $mozi->id, 'name' => 'Nubank', 'type' => 'checking', 'balance' => 1000]);

        $contact = Contact::create(['user_id' => $this->user->id, 'name' => 'Mozi', 'linked_user_id' => $mozi->id]);
        Contact::create(['user_id' => $mozi->id, 'name' => 'Rhaniel', 'linked_user_id' => $this->user->id]);

        // Boleto de amanhã, dividido, pago pela Mozi.
        $this->store([
            'date' => '2026-11-19',
            'account_id' => null,
            'split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $contact->id]],
                'paid_by_contact_id' => $contact->id,
            ],
        ]);
        $source = Transaction::where('user_id', $this->user->id)->firstOrFail();

        $this->actingAs($mozi)
            ->post(route('shares.accept', Share::firstOrFail()), [
                'category_id' => Category::where('user_id', $mozi->id)->where('name', 'Outros')->value('id'),
                'account_id' => $moziAccount->id,
            ])
            ->assertSessionHasNoErrors();
        $mirror = Transaction::where('user_id', $mozi->id)->firstOrFail();

        // Eu não pago esse boleto: não posso marcar.
        $this->actingAs($this->user)
            ->post(route('transactions.pay', $source))
            ->assertSessionHasErrors('paid');
        $this->assertNull($source->fresh()->paid_at);

        // Ela marca na cópia dela: vale para as duas, e o total sai da conta dela.
        $this->actingAs($mozi)->post(route('transactions.pay', $mirror))->assertSessionHasNoErrors();

        $this->assertNotNull($source->fresh()->paid_at);
        $this->assertNotNull($mirror->fresh()->paid_at);
        $this->assertEquals(900.0, (float) $moziAccount->fresh()->balance);
        $this->assertEquals(1000.0, $this->balance());
    }

    public function test_turning_on_auto_pay_settles_overdue_parcels(): void
    {
        $this->store(['is_installment' => true, 'installments_count' => 3]);
        $installment = \App\Models\Installment::firstOrFail();

        $this->travelTo('2026-12-20 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();
        $this->assertEquals(900.0, $this->balance()); // 2ª parcela atrasada

        $this->actingAs($this->user)
            ->post(route('installments.auto-pay', $installment), ['enabled' => true])
            ->assertRedirect();

        $this->assertTrue($installment->fresh()->auto_pay);
        $this->assertSame('2026-12-18', Transaction::where('installment_number', 2)->firstOrFail()->paid_at->toDateString());
        $this->assertEquals(800.0, $this->balance());

        $this->actingAs(User::factory()->create())
            ->post(route('installments.auto-pay', $installment), ['enabled' => false])
            ->assertNotFound();
    }

    public function test_moving_a_paid_transaction_to_the_future_makes_it_pending_and_restores_the_balance(): void
    {
        $this->store(['description' => 'Telefone', 'amount' => 625]);
        $transaction = Transaction::where('description', 'Telefone')->firstOrFail();

        $this->assertNotNull($transaction->paid_at);
        $this->assertEqualsWithDelta(375.0, $this->balance(), 0.001);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Telefone',
                'amount' => 625,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-12-04',
            ])
            ->assertSessionHasNoErrors();

        $transaction->refresh();
        $this->assertNull($transaction->paid_at);
        $this->assertFalse((bool) $transaction->balance_applied);
        $this->assertEqualsWithDelta(1000.0, $this->balance(), 0.001);
    }

    public function test_editing_without_changing_the_date_keeps_the_status(): void
    {
        $this->store(['description' => 'Futuro', 'date' => '2026-12-10']);
        $transaction = Transaction::where('description', 'Futuro')->firstOrFail();

        $this->actingAs($this->user)->post(route('transactions.pay', $transaction));
        $this->assertNotNull($transaction->fresh()->paid_at);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Futuro (editado)',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-12-10',
            ])
            ->assertSessionHasNoErrors();

        $this->assertNotNull($transaction->fresh()->paid_at);
        $this->assertEqualsWithDelta(900.0, $this->balance(), 0.001);
    }
}
