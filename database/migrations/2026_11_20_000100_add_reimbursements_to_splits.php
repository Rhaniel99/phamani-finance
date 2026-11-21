<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Compra para outra pessoa ("A receber").
 *
 * Uma compra feita por você em que a sua parte é zero (ex.: o irmão usa o cartão) fica "a receber"
 * de cada contato da divisão. Quando ele devolve (Pix), a parte dele é marcada como recebida:
 * - reimbursed_at: data em que o dinheiro chegou;
 * - reimbursement_account_id: conta onde caiu (o saldo dela sobe, sem contar como receita);
 * - reimbursed_amount: quanto entrou (para desfazer exatamente o mesmo valor).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transaction_splits', function (Blueprint $table) {
            $table->date('reimbursed_at')->nullable();
            $table->foreignUuid('reimbursement_account_id')->nullable()->constrained('accounts')->nullOnDelete();
            $table->decimal('reimbursed_amount', 12, 2)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('transaction_splits', function (Blueprint $table) {
            $table->dropConstrainedForeignId('reimbursement_account_id');
            $table->dropColumn(['reimbursed_at', 'reimbursed_amount']);
        });
    }
};
