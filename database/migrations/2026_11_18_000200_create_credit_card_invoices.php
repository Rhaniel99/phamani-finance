<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Fase 2 — cartão de crédito com limite e fatura.
 *
 * - accounts (tipo "credit"): limite, dia de fechamento, dia de vencimento e conta que paga a fatura.
 * - credit_card_invoices: uma fatura por cartão e mês de vencimento.
 * - transactions.invoice_id: em qual fatura a compra caiu.
 *
 * Compras no cartão não mexem em saldo de conta; o dinheiro só sai ao pagar a fatura.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('accounts', function (Blueprint $table) {
            $table->decimal('credit_limit', 12, 2)->nullable();
            $table->unsignedTinyInteger('closing_day')->nullable();
            $table->unsignedTinyInteger('due_day')->nullable();
            $table->foreignUuid('payment_account_id')->nullable()->constrained('accounts')->nullOnDelete();
        });

        Schema::create('credit_card_invoices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('account_id')->constrained()->cascadeOnDelete();
            // 1º dia do mês de vencimento: "fatura de dezembro".
            $table->date('reference_month');
            $table->date('closing_date');
            $table->date('due_date');
            $table->date('paid_at')->nullable();
            $table->decimal('paid_amount', 12, 2)->nullable();
            $table->foreignUuid('paid_from_account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->timestamps();

            $table->unique(['account_id', 'reference_month']);
            $table->index(['user_id', 'paid_at']);
        });

        Schema::table('transactions', function (Blueprint $table) {
            $table->foreignUuid('invoice_id')->nullable()->constrained('credit_card_invoices')->nullOnDelete();
        });

        // Transações já lançadas em contas "Crédito" deixam de mexer no saldo:
        // o saldo do cartão volta a zero e a dívida passa a ser a fatura.
        DB::transaction(function () {
            $creditAccounts = DB::table('accounts')->where('type', 'credit')->pluck('id');

            $applied = DB::table('transactions')
                ->whereIn('account_id', $creditAccounts)
                ->where('balance_applied', true)
                ->get(['id', 'account_id', 'type', 'amount']);

            foreach ($applied as $t) {
                $delta = $t->type === 'income' ? -(float) $t->amount : (float) $t->amount;

                DB::table('accounts')->where('id', $t->account_id)->increment('balance', $delta);
                DB::table('transactions')->where('id', $t->id)->update(['balance_applied' => false]);
            }
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropConstrainedForeignId('invoice_id');
        });

        Schema::dropIfExists('credit_card_invoices');

        Schema::table('accounts', function (Blueprint $table) {
            $table->dropConstrainedForeignId('payment_account_id');
            $table->dropColumn(['credit_limit', 'closing_day', 'due_day']);
        });
    }
};
