import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/portal_models.dart';
import '../../services/portal_service.dart';
import '../../services/portal_auth_service.dart';
import '../../services/championship_service.dart';
import '../../models/team_model.dart';

class PortalAdminModals {
  
  static void showCreateUserModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String name = '';
    String username = '';
    String password = '';
    String role = 'athlete';
    String? teamId;

    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Novo Membro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
                    onSaved: (val) => name = val ?? '',
                    validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Username (sem espaços)', border: OutlineInputBorder()),
                    onSaved: (val) => username = val ?? '',
                    validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Senha Provisória', border: OutlineInputBorder()),
                    obscureText: true,
                    onSaved: (val) => password = val ?? '',
                    validator: (val) => val!.length < 6 ? 'Mínimo de 6 caracteres' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Papel (Role)', border: OutlineInputBorder()),
                    value: role,
                    items: const [
                      DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                      DropdownMenuItem(value: 'staff', child: Text('Comissão Técnica (Staff)')),
                      DropdownMenuItem(value: 'president', child: Text('Presidente')),
                      DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                    ],
                    onChanged: (val) => setState(() => role = val!),
                  ),
                  const SizedBox(height: 12),
                  if (role == 'athlete' || role == 'staff')
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Equipe (ID Opcional)', border: OutlineInputBorder()),
                      onSaved: (val) => teamId = val,
                    ),
                  const SizedBox(height: 24),
                  isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            formKey.currentState!.save();
                            setState(() => isLoading = true);
                            
                            final authService = Provider.of<PortalAuthService>(context, listen: false);
                            final error = await authService.createUserAccess(username, password, name, role, teamId: teamId);
                            
                            setState(() => isLoading = false);
                            if (error != null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
                            } else {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Usuário criado com sucesso!'), backgroundColor: Colors.green));
                              Navigator.pop(ctx);
                            }
                          }
                        },
                        child: const Text('CRIAR ACESSO'),
                      ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void showCreateDueModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String title = '';
    double amount = 0;
    DateTime? dueDate;
    String targetType = 'individual'; // 'all', 'team', 'individual'
    String? targetTeamId;
    String? targetUserId;

    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          final portalService = Provider.of<PortalService>(context, listen: false);
          
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Lançar Novo Débito', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Destinatário', border: OutlineInputBorder()),
                    value: targetType,
                    items: const [
                      DropdownMenuItem(value: 'individual', child: Text('Atleta Específico')),
                      DropdownMenuItem(value: 'team', child: Text('Equipe Específica')),
                      DropdownMenuItem(value: 'all', child: Text('Todos os Atletas')),
                    ],
                    onChanged: (val) => setState(() => targetType = val!),
                  ),
                  const SizedBox(height: 12),

                  if (targetType == 'individual')
                    StreamBuilder<List<PortalUser>>(
                      stream: portalService.streamAllUsers(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Selecione o Atleta', border: OutlineInputBorder()),
                          value: targetUserId,
                          items: snapshot.data!.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name))).toList(),
                          onChanged: (val) => setState(() => targetUserId = val),
                          validator: (val) => val == null ? 'Selecione um atleta' : null,
                        );
                      }
                    ),

                  if (targetType == 'team')
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'ID da Equipe', border: OutlineInputBorder()),
                      onSaved: (val) => targetTeamId = val,
                      validator: (val) => val!.isEmpty ? 'Informe o ID' : null,
                    ),

                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Título do Débito', border: OutlineInputBorder()),
                    onSaved: (val) => title = val ?? '',
                    validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(labelText: 'Valor (R\$)', border: OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onSaved: (val) => amount = double.tryParse(val?.replaceAll(',', '.') ?? '0') ?? 0,
                          validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setState(() => dueDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Vencimento', border: OutlineInputBorder()),
                            child: Text(dueDate != null ? DateFormat('dd/MM/yyyy').format(dueDate!) : 'Selecionar'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () async {
                          if (formKey.currentState!.validate() && dueDate != null) {
                            formKey.currentState!.save();
                            setState(() => isLoading = true);
                            
                            try {
                              if (targetType == 'individual') {
                                final userDoc = await portalService.getUser(targetUserId!);
                                await portalService.createFinancialDue(PortalFinancialDue(
                                  id: '', userId: targetUserId!, userName: userDoc?.name, title: title, amount: amount, dueDate: dueDate!, status: 'pending'
                                ));
                              } else if (targetType == 'all') {
                                await portalService.createBatchDues(title, amount, dueDate!, null);
                              } else if (targetType == 'team') {
                                await portalService.createBatchDues(title, amount, dueDate!, targetTeamId);
                              }
                              
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Débito(s) lançado(s) com sucesso!'), backgroundColor: Colors.green));
                                Navigator.pop(ctx);
                              }
                            } catch (e) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: '), backgroundColor: Colors.red));
                            } finally {
                              setState(() => isLoading = false);
                            }
                          } else if (dueDate == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Selecione o Vencimento!'), backgroundColor: Colors.red));
                          }
                        },
                        child: const Text('LANÇAR DÉBITO'),
                      ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void showCreateEventModal(BuildContext context, PortalUser currentUser) {
    final formKey = GlobalKey<FormState>();
    String title = '';
    String description = '';
    String location = '';
    DateTime? eventDate;
    TimeOfDay? eventTime;
    String? teamId = currentUser.role == 'president' ? currentUser.teamId : null;
    String targetRole = 'all';

    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          final portalService = Provider.of<PortalService>(context, listen: false);
          final champService = Provider.of<ChampionshipService>(context, listen: false);
          
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Novo Evento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                    onSaved: (val) => title = val ?? '',
                    validator: (val) => val!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Local', border: OutlineInputBorder()),
                    onSaved: (val) => location = val ?? '',
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) setState(() => eventDate = date);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Data', border: OutlineInputBorder()),
                            child: Text(eventDate != null ? DateFormat('dd/MM/yyyy').format(eventDate!) : 'Selecionar'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                            if (time != null) setState(() => eventTime = time);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Hora', border: OutlineInputBorder()),
                            child: Text(eventTime != null ? eventTime!.format(ctx) : 'Selecionar'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  if (currentUser.role == 'admin')
                    DropdownButtonFormField<String?>(
                      decoration: const InputDecoration(labelText: 'Equipe Convocada (Opcional - deixe vazio p/ todos)', border: OutlineInputBorder()),
                      value: teamId,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Todos os Times (Global)')),
                        ...champService.teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                      ],
                      onChanged: (val) => setState(() => teamId = val),
                    ),

                  
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Público Alvo', border: OutlineInputBorder()),
                    value: targetRole,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos os Atletas')),
                      DropdownMenuItem(value: 'president', child: Text('Apenas Presidentes')),
                    ],
                    onChanged: (val) => setState(() => targetRole = val!),
                  ),
const SizedBox(height: 24),
                  isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () async {
                          if (formKey.currentState!.validate() && eventDate != null && eventTime != null) {
                            formKey.currentState!.save();
                            setState(() => isLoading = true);
                            
                            try {
                              final finalDateTime = DateTime(eventDate!.year, eventDate!.month, eventDate!.day, eventTime!.hour, eventTime!.minute);
                              await portalService.createEvent(PortalEvent(id: '', title: title, date: finalDateTime, location: location, description: description, teamId: teamId, targetRole: targetRole));
                              
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Evento criado!'), backgroundColor: Colors.green));
                                Navigator.pop(ctx);
                              }
                            } catch (e) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: '), backgroundColor: Colors.red));
                            } finally {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                        child: const Text('CRIAR EVENTO'),
                      ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void showEditUserModal(BuildContext context, PortalUser user) {
    final formKey = GlobalKey<FormState>();
    String name = user.name;
    String role = user.role;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          final portalService = Provider.of<PortalService>(context, listen: false);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Editar Membro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
                    onSaved: (val) => name = val ?? '',
                    validator: (val) => val!.isEmpty ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Nível de Acesso', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'athlete', child: Text('Atleta (Comum)')),
                      DropdownMenuItem(value: 'staff', child: Text('Comissão Técnica')),
                      DropdownMenuItem(value: 'president', child: Text('Presidente de Time')),
                      DropdownMenuItem(value: 'admin', child: Text('Administrador FJF')),
                    ],
                    onChanged: (val) => setState(() => role = val!),
                  ),
                  const SizedBox(height: 24),
                  isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            formKey.currentState!.save();
                            setState(() => isLoading = true);
                            try {
                              await portalService.updateUser(user.id, {'name': name, 'role': role});
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                            } finally {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                        child: const Text('SALVAR'),
                      ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void showEditEventModal(BuildContext context, PortalEvent event) {
    final formKey = GlobalKey<FormState>();
    String title = event.title;
    String location = event.location;
    String description = event.description;
    DateTime eventDate = event.date;
    TimeOfDay eventTime = TimeOfDay(hour: event.date.hour, minute: event.date.minute);
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          final portalService = Provider.of<PortalService>(context, listen: false);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Editar Evento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: title,
                    decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                    onSaved: (val) => title = val ?? '',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: ctx, initialDate: eventDate, firstDate: DateTime(2000), lastDate: DateTime(2100),
                            );
                            if (date != null) setState(() => eventDate = date);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Data', border: OutlineInputBorder()),
                            child: Text(DateFormat('dd/MM/yyyy').format(eventDate)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final time = await showTimePicker(context: ctx, initialTime: eventTime);
                            if (time != null) setState(() => eventTime = time);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Hora', border: OutlineInputBorder()),
                            child: Text(eventTime.format(ctx)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            formKey.currentState!.save();
                            setState(() => isLoading = true);
                            try {
                              final finalDateTime = DateTime(eventDate.year, eventDate.month, eventDate.day, eventTime.hour, eventTime.minute);
                              await portalService.updateEvent(event.id, {
                                'title': title,
                                'date': Timestamp.fromDate(finalDateTime),
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                            } finally {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                        child: const Text('SALVAR'),
                      ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void showEditDueModal(BuildContext context, PortalFinancialDue due) {
    final formKey = GlobalKey<FormState>();
    double amount = due.amount;
    DateTime dueDate = due.dueDate;
    String status = due.status;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          final portalService = Provider.of<PortalService>(context, listen: false);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Editar Débito', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: amount.toStringAsFixed(2),
                    decoration: const InputDecoration(labelText: 'Valor (R\$)', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onSaved: (val) => amount = double.tryParse(val?.replaceAll(',', '.') ?? '0') ?? 0,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                      DropdownMenuItem(value: 'under_review', child: Text('Em Análise')),
                      DropdownMenuItem(value: 'paid', child: Text('Pago')),
                    ],
                    onChanged: (val) => setState(() => status = val!),
                  ),
                  const SizedBox(height: 24),
                  isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            formKey.currentState!.save();
                            setState(() => isLoading = true);
                            try {
                              await portalService.updateDue(due.id, {
                                'amount': amount,
                                'status': status,
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                            } finally {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                        child: const Text('SALVAR'),
                      ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
